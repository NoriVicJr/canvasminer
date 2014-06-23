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
  haml :accounts
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

  haml :courses
end

get '/course_data.csv' do
  @canvas_url = session[:canvas_url]
  @access_token = session[:access_token]
  @course_id = params[:course_id]

  content_type 'application/csv'

  CSV.generate do |csv|
    csv << ['Student', 'Page Views']

    # Get the students list
    students_request = typhoeus_request "/courses/#{@course_id}/students"
    students_request.on_success do |students_response|

      # Extract students
      students = JSON.parse students_response.response_body

      # Initialize parallel requests
      hydra = Typhoeus::Hydra.new

      # Queue: Get the course info
      hydra.queue course_request = typhoeus_request("/courses/#{@course_id}")
      course_request.on_success{ |course_response| attachment("#{JSON.parse(course_response.body)['name']}.csv")}

      # Loop all students from course
      for student in students
        # Get the student's activity
        hydra.queue student_activity_request = typhoeus_request("/courses/#{@course_id}/analytics/users/#{student['id']}/activity", body: { student: student })

        # Response callback
        student_activity_request.on_success do |student_activity_response|
          student = student_activity_response.request.original_options[:body][:student]

          # Extract activity
          student_activity = JSON.parse student_activity_response.response_body

          # Exctract the page views
          student_page_views = student_activity['page_views'].values.inject(:+) if student_activity['page_views']
          student_page_views ||= 0

          # Fill the csv file
          csv << [student['name'], student_page_views]
        end
      end

      # Execute the requests
      hydra.run

    end
    students_request.run
  end

end

def typhoeus_request(path, options = {})
  puts "#{@canvas_url}/api/v1#{path}"
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
  puts "#{@canvas_url}/api/v1#{path}"
  begin
    RestClient.get "https://#{@canvas_url}/api/v1#{path}?access_token=#{@access_token}" do |response, request, result, &block|
      puts "RESPONSE: #{response.code}"
      if response.code != 200
        puts "Yay"
        @message = "<b>Canvas rejected the request, probably not authorized.</b> <br>Response: #{response}"
        haml :home
        break
      else
        puts response
        return JSON.parse(response)
      end
    end
  rescue
    @message = "Please fill in this first"
    haml :home
  end
end
