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

  @course = api_request "/courses/#{@course_id}"
  @students = api_request "/courses/#{@course_id}/students"


  content_type 'application/csv'
  attachment "#{@course['name']}.csv"

  CSV.generate do |csv|
    csv << ['Student', 'Page Views']
    @students.each do |student|

      student_activity = api_request "/courses/#{@course_id}/analytics/users/#{student['id']}/activity"

      student_page_views = student_activity['page_views'].values.inject(:+) if student_activity['page_views']
      student_page_views ||= 0

      csv << [student['name'], student_page_views]

    end
  end

end



def api_request(path)
  puts "#{@canvas_url}/api/v1#{path}"
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
