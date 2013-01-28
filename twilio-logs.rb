# Sinatra app that gathers voice and sms log data from Twilio and exports as csv
require 'sinatra'
require 'erb'
require 'twiliolib'
require 'twiliolib-patch'
require 'nokogiri'
require "fastercsv"

API_VERSION = '2010-04-01'
PAGE_SIZE=500

def get_calls(starttime,endtime,pagesize,page)
  #make a REST call to Twilio Calls resource
  account = Twilio::RestAccount.new(params[:account_sid], params[:auth_token])
  d = { "StartTime>" => starttime,  "StartTime<" => endtime,"PageSize" => pagesize,"Page" => page}
  resp = account.request("/#{API_VERSION}/Accounts/#{params[:account_sid]}/Calls", 'GET', d)
end

def get_sms(starttime,endtime,pagesize,page)
  #make a REST call to Twilio SMS/Messages resource
  account = Twilio::RestAccount.new(params[:account_sid], params[:auth_token])
  d = { "DateSent>" => starttime,  "DateSent<" => endtime,"PageSize" => pagesize,"Page" => page}
  resp = account.request("/#{API_VERSION}/Accounts/#{params[:account_sid]}/SMS/Messages", 'GET', d)
end

def parse_call_record(node)
  #parse calls xml result and return as a csv friendly array
  call={}
  node.children.each do |child|
    call[child.name]=child.content
  end
  call_mins=(call["Duration"].to_f/60).ceil
  price_per_min = 0 if call_mins==0
  price_per_min = price_per_min = (call["Price"].to_f.abs)/call_mins if call_mins!=0
  [call["From"],call["To"],call["StartTime"],call["EndTime"],call_mins,price_per_min,call["Price"].to_f.abs,call["Status"],call["Sid"]]
end


def parse_sms_record(node)
  #parse sms xml result and return as a csv friendly array
  sms={}
  node.children.each do |child|
    sms[child.name]=child.content
  end
  [sms["From"],sms["To"],sms["Body"],sms["DateSent"],sms["Price"].to_f.abs,sms["Status"],sms["Sid"]]
end

def csv_output
  #generate csv export for calls
  resp = get_calls(params[:start_date],params[:end_date],PAGE_SIZE,0) #fetch initial page of results
  resp.error! unless resp.kind_of? Net::HTTPSuccess
  doc  = Nokogiri::XML(resp.body)
  numpages=((doc.xpath("//Calls").first.attributes["numpages"].value).to_i)-1
  return "Result too large, try a smaller date range" if numpages > 60
  puts "#{numpages} pages to fetch"
  csv_string = FasterCSV.generate do |csv|
    csv << ["From","To","Call Start Time","Call End Time","Call Duration (minutes)","Call Price per Minute","Total Call Cost","Call Status","Call SID"] #header row
    #output page of calls
    calls=doc.xpath("//Call")
    calls.each do |call|
       csv << parse_call_record(call)
    end
    (1..numpages).each do |page| #iterate over remaining pages
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

def sms_csv_output
  #generate csv export for sms messages
  resp = get_sms(params[:start_date],params[:end_date],PAGE_SIZE,0)   #fetch initial page
  resp.error! unless resp.kind_of? Net::HTTPSuccess
  doc  = Nokogiri::XML(resp.body)
  numpages=((doc.xpath("//SMSMessages").first.attributes["numpages"].value).to_i)-1
  return "Result too large, try a smaller date range" if numpages > 30
  puts "#{numpages} pages to fetch"
  csv_string = FasterCSV.generate do |csv|
    csv << ["From","To","Body","Semt Time","Price","Status","SMS SID"] #csv header row
    #output page of calls
    calls=doc.xpath("//SMSMessage")
    calls.each do |sms|
       csv << parse_sms_record(sms)
    end
    (1..numpages).each do |page| #iterate over remaining pages
      puts "fetching #{page}/#{numpages}..."
      resp = get_sms(params[:start_date],params[:end_date],PAGE_SIZE,page)
      resp.error! unless resp.kind_of? Net::HTTPSuccess
      pagedoc  = Nokogiri::XML(resp.body)
      calls=pagedoc.xpath("//SMSMessage")
      calls.each do |sms|
         csv << parse_sms_record(sms)
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
  rescue Exception => e  
    "error validating parameters, please ensure account and auth token are correct and dates are in the format of YYYY-MM-DD and try again. #{e.message}"
  end
end

post '/sms' do
  begin
    headers "Content-Disposition" => "attachment;filename=report.csv", "Content-Type" => "application/octet-stream"
    sms_csv_output
  rescue
    "error validating parameters, please ensure account and auth token are correct and dates are in the format of YYYY-MM-DD and try again."
  end
end
