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

  content_type 'application/csv'

  @users = api_request "/courses/#{@course_id}/students"

  # Get the students list
  # students_request = typhoeus_request "/courses/#{@course_id}/students"
  # students_request.on_success do |students_response|
  #
  #   # Extract students
  #   users = JSON.parse students_response.response_body
  #   puts "-----------------"
  #   puts users
  #   puts "-----------------"
  #   puts @users
  #   puts "-----------------"
  # end
  # students_request.run

  @course_summary = api_request "/courses/#{@course_id}/analytics/student_summaries"

  CSV.generate(col_sep: ";") do |csv|
    csv << ['Student id', 'Student Name', 'Student Sortable Name', 'Student Short Name', 'Student Login Id', 'Course Page Views', 'Course Participations', 'Instructor Messages', 'Student Messages']
    # Initialize parallel requests
    hydra = Typhoeus::Hydra.new

    # Loop trough users
    @course_summary.each do |student_summary|
      # Get the student's communication summary
      hydra.queue student_cummunication_request = typhoeus_request("/courses/#{@course_id}/analytics/users/#{student_summary['id']}/communication", body: { student_id: student_summary['id'] })

      student_cummunication_request.on_success do |student_communication_response|
        # Extract cummunication
        student_communication = JSON.parse student_communication_response.response_body
        instructorMessages = 0
        studentMessages = 0
        student_communication.values.each do |hash|
          instructorMessages += hash['instructorMessages'].to_i
          studentMessages += hash['studentMessages'].to_i
        end

        # Get student_id from original request
        student_id = student_communication_response.request.original_options[:body][:student_id]

        # Get student
        student = @users.select{|user| user['id'] == student_id }.first

        # Get student's course_summary
        student_summary = @course_summary.select{ |user| user['id'] == student_id }.first

        # Fill the csv file
        puts "-----> Data for student #{student_id} added to csv"
        # puts "Student: #{student}"
        # puts "Summary: #{student_summary}"
        # puts "Communi: #{student_communication}"
        # puts "Instruc: #{instructorMessages}"
        # puts "Student: #{studentMessages}"

        csv << [student['id'], student['name'], student['sortable_name'], student['short_name'], student['login_id'], student_summary['page_views'], student_summary['participations'], instructorMessages, studentMessages] if student && student_summary && student_communication
      end



      # # Fill the csv file
      # puts "Data for student #{student['id']} added to csv"
      # csv << [student['id'], student['name'], student['sortable_name'], student['short_name'], student['login_id'], student_summary['page_views']]
    end

    # Execute the requests
    hydra.run
  end

end

def typhoeus_request(path, options = {})
  puts "Typhoeus requesting: #{@canvas_url}/api/v1#{path}"
  begin
    request = Typhoeus::Request.new "https://#{@canvas_url}/api/v1#{path}", headers: { Authorization: "Bearer #{@access_token}" }, body: options[:body]
    request.on_failure do |response|
      @message = "<b>Canvas rejected the request, probably not authorized.</b> <br>Response: #{response}"
      haml :home
    end
    return request
  rescue
    @message = "Could not create a valid request..."
    haml :home
  end
end

def api_request(path)
  puts "Single request: #{@canvas_url}/api/v1#{path}"
  begin
    RestClient.get "https://#{@canvas_url}/api/v1#{path}?access_token=#{@access_token}" do |response, request, result, &block|
      if response.code != 200
        @message = "<b>Canvas rejected the request, probably not authorized.</b> <br>Response: #{response}"
        haml :home
      else
        # puts response
        return JSON.parse(response)
      end
    end
  rescue
    @message = "Please fill in this first"
    haml :home
  end
end
