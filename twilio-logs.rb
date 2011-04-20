#!/usr/bin/env ruby
require 'sinatra'
require 'erb'
require 'twiliolib'
require 'twiliolib-monkeypatch'
require 'nokogiri'
require "fastercsv"

API_VERSION = '2010-04-01'
PAGE_SIZE=500

def get_calls(starttime,endtime,pagesize,page)
  #make a REST call toi Twilio
  account = Twilio::RestAccount.new(params[:account_sid], params[:auth_token])
  d = { "StartTime>" => starttime,  "EndTime<" => endtime,"PageSize" => pagesize,"Page" => page}
  resp = account.request("/#{API_VERSION}/Accounts/#{params[:account_sid]}/Calls", 'GET', d)
end

def parse_call_record(node)
  call={}
  node.children.each do |child|
    call[child.name]=child.content
  end
  call_mins=(call["Duration"].to_f/60).ceil
  price_per_min = 0 if call_mins==0
  price_per_min = price_per_min = (call["Price"].to_f.abs)/call_mins if call_mins!=0
  [call["From"],call["To"],call["StartTime"],call["EndTime"],call_mins,price_per_min,call["Price"].to_f.abs,call["Status"],call["Sid"]]
end

def csv_output
  #fetch initial page
  resp = get_calls(params[:start_date],params[:end_date],PAGE_SIZE,0)
  resp.error! unless resp.kind_of? Net::HTTPSuccess
  doc  = Nokogiri::XML(resp.body)
  numpages=((doc.xpath("//Calls").first.attributes["numpages"].value).to_i)-1
  puts "#{numpages} pages to fetch"
  csv_string = FasterCSV.generate do |csv|
    csv << ["From","To","Call Start Time","Call End Time","Call Duration (minutes)","Call Price per Minute","Total Call Cost","Call Status","Call SID"]
    #first page of calls
    calls=doc.xpath("//Call")
    calls.each do |call|
       csv << parse_call_record(call)
    end
    (1..numpages).each do |page|
      puts "fetching #{page}/#{numpages}..."
      resp = get_calls(params[:start_date],params[:end_date],PAGE_SIZE,page)
      resp.error! unless resp.kind_of? Net::HTTPSuccess
      pagedoc  = Nokogiri::XML(resp.body)
      calls=pagedoc.xpath("//Call")
      calls.each do |call|
         csv << parse_call_record(call)
      end
    end
	
  end
  csv_string
end

get '/' do
  erb :index
end

post '/' do
  begin
    headers "Content-Disposition" => "attachment;filename=report.csv", "Content-Type" => "application/octet-stream"
    csv_output
  rescue
    "error validating parameters, please ensure account and auth token are correct and dates are in the format of YYYY-MM-DD and try again."
  end
end
 