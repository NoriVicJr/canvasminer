#!/usr/bin/env ruby

# dev hint: shotgun app.rb
Bundler.require

get '/' do
  'This is a sinatra app!'
end
