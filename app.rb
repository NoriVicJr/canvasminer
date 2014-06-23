#!/usr/bin/env ruby

# dev hint: shotgun app.rb
Bundler.require
require 'csv'

# Configuration
enable :sessions
set :session_secret, "9d8fda43972bdaed69d57703fa4b7d7d"

get '/' do
  @canvas_url = session[:canvas_url]
  @access_token = session[:access_token]
  haml :home
end

post '/set_url_and_token' do
  session.clear
  session[:canvas_url] = params[:canvas_url] if params[:canvas_url]
  session[:access_token] = params[:access_token] if params[:access_token]

  redirect '/accounts'
end

get '/accounts' do
  @canvas_url = session[:canvas_url]
  @access_token = session[:access_token]
  @accounts = api_request '/accounts'
  if @accounts.class.to_s != 'String'
    haml :accounts
  else
    haml :home
  end
end

post '/set_account' do
  session[:account_id] = params[:account_id] if params[:account_id]

  redirect '/courses'
end

get '/clear' do
  session.clear
  @message = "Settings cleared from cookies"
  haml :home
end

get '/courses' do
  @canvas_url = session[:canvas_url]
  @access_token = session[:access_token]
  @account_id = session[:account_id]
  @courses = api_request "/accounts/#{@account_id}/courses"
  if @courses.class.to_s != 'String'
    haml :courses
  else
    haml :home
  end
end

get '/course_data.csv' do
  @canvas_url = session[:canvas_url]
  @access_token = session[:access_token]
  @course_id = params[:course_id]

  # Set the type to csv and set the name of the file to the course name wich is retrieved from the api
  content_type 'application/csv'
  @course = api_request "/courses/#{@course_id}"
  attachment("#{@course['name']}.csv")

  # Get all users
  @users = api_request "/courses/#{@course_id}/students"

  # Initialize parallel requests
  hydra = Typhoeus::Hydra.new

  # Loop all users
  for user in @users
    # Get the user's activity
    hydra.queue student_activity_request = typhoeus_request("/courses/#{@course_id}/analytics/users/#{user['id']}/activity", body: { user_id: user['id'] })
    student_activity_request.on_success do |student_activity_response|
      # Get the original user_id
      user_id = student_activity_response.request.original_options[:body][:user_id]

      # Exctract the page views and participations
      student_activity = JSON.parse(student_activity_response.response_body)
      student_page_views = student_activity['page_views'].values.inject(:+) if student_activity['page_views']
      student_page_views ||= 0
      student_participations = student_activity['participations'].count

      # Set the page views and participations
      user = @users.select{|user| user['id'] == user_id }.first
      user['page_views'] = student_page_views
      user['participations'] = student_participations
    end

    # Get the user's communication
    hydra.queue student_cummunication_request = typhoeus_request("/courses/#{@course_id}/analytics/users/#{user['id']}/communication", body: { user_id: user['id'] })
    student_cummunication_request.on_success do |student_communication_response|
      # Get the original user_id
      user_id = student_communication_response.request.original_options[:body][:user_id]

      # Extract cummunication
      student_communication = JSON.parse student_communication_response.response_body
      instructorMessages = 0
      studentMessages = 0
      student_communication.values.each do |hash|
        instructorMessages += hash['instructorMessages'].to_i
        studentMessages += hash['studentMessages'].to_i
      end

      # Set the page views and participations
      user = @users.select{|user| user['id'] == user_id }.first
      user['instructor_messages'] = instructorMessages
      user['student_messages'] = studentMessages
    end

  end
  # Execute all requests
  hydra.run

  # Generate the csv file
  CSV.generate(col_sep: ";") do |csv|
    csv << ['Student id', 'Student Name', 'Student Sortable Name', 'Student Short Name', 'Student Login Id', 'Course Page Views', 'Course Participations', 'Instructor Messages', 'Student Messages']
    @users.each do |user|
      csv << [user['id'], user['name'], user['sortable_name'], user['short_name'], user['login_id'], user['page_views'], user['participations'], user['instructor_messages'], user['student_messages']]
    end
  end

end

def typhoeus_request(path, options = {})
  # puts "Typhoeus requesting: #{@canvas_url}/api/v1#{path}"
  begin
    request = Typhoeus::Request.new "https://#{@canvas_url}/api/v1#{path}", headers: { Authorization: "Bearer #{@access_token}" }, body: options[:body]
    request.on_failure do |response|
      @message = "<b>Canvas rejected the request, probably not authorized.</b> <br>Response: #{Rack::Utils.escape_html(response)}"
      haml :home
    end
    return request
  rescue
    @message = "Could not create a valid request..."
    haml :home
  end
end

def api_request(path)
  # puts "Single request: #{@canvas_url}/api/v1#{path}"
  begin
    RestClient.get "https://#{@canvas_url}/api/v1#{path}?access_token=#{@access_token}" do |response, request, result, &block|
      if response.code != 200
        @message = "<b>Canvas rejected the request, probably not authorized.</b> <br>Response: #{Rack::Utils.escape_html(response)}"
        haml :home
      else
        return JSON.parse(response)
      end
    end
  rescue
    @message = "Please fill in this first"
    haml :home
  end
end
