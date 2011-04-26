# Sinatra app that gathers voice and sms log data from Twilio and exports as csv
require 'sinatra'
require 'erb'
require 'twiliolib'
require 'twiliolib-patch'
require 'nokogiri'
require "fastercsv"

API_VERSION = '2010-04-01'
PAGE_SIZE=500
CALL_CSV_HEADERS=["From","To","Call Start Time","Call End Time","Call Duration (minutes)","Call Price per Minute","Total Call Cost","Call Status","Call SID"] #header row
SMS_CSV_HEADERS=["From","To","Body","Semt Time","Price","Status","SMS SID"] #csv header row

def get_calls(starttime,endtime,pagesize,page)
  #make a REST call to Twilio Calls List resource http://www.twilio.com/docs/api/rest/call#list
  account = Twilio::RestAccount.new(params[:account_sid], params[:auth_token])
  d = { "StartTime>" => starttime,  "EndTime<" => endtime,"PageSize" => pagesize,"Page" => page}
  resp = account.request("/#{API_VERSION}/Accounts/#{params[:account_sid]}/Calls", 'GET', d)
end

def get_sms(starttime,endtime,pagesize,page)
  #make a REST call to Twilio SMS Messages List resource http://www.twilio.com/docs/api/rest/sms#list
  account = Twilio::RestAccount.new(params[:account_sid], params[:auth_token])
  d = { "DateSent>" => starttime,  "DateSent<" => endtime,"PageSize" => pagesize,"Page" => page}
  resp = account.request("/#{API_VERSION}/Accounts/#{params[:account_sid]}/SMS/Messages", 'GET', d)
end

def parse_call_record(node)
  #parses call xml into a csv friendly array
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
  #parses sms xml into a csv friendly array
  sms={}
  node.children.each do |child|
    sms[child.name]=child.content
  end
  [sms["From"],sms["To"],sms["Body"],sms["DateSent"],sms["Price"].to_f.abs,sms["Status"],sms["Sid"]]
end

def csv_output(resource)
  #generate csv output

  if resource=="calls"
    container_xpath="//Calls"
    resource_xpath="//Call"
    csv_headers=CALL_CSV_HEADERS
    resp = get_calls(params[:start_date],params[:end_date],PAGE_SIZE,0) #fetch initial page of results
  elsif resource=="sms"
    container_xpath="//SMSMessages"
    resource_xpath="//SMSMessage"
    csv_headers=SMS_CSV_HEADERS
    resp = get_sms(params[:start_date],params[:end_date],PAGE_SIZE,0)    #fetch initial page of results
  end
  
  resp.error! unless resp.kind_of? Net::HTTPSuccess
  doc  = Nokogiri::XML(resp.body)
  numpages=((doc.xpath(container_xpath).first.attributes["numpages"].value).to_i)-1
  return "Result too large, try a smaller date range" if numpages > 30
  puts "#{numpages} pages to fetch"

  #construct csv output
  csv_string = FasterCSV.generate do |csv|
    csv << csv_headers #header row
    #output page of calls
    calls=doc.xpath(resource_xpath)
    calls.each do |call|
      if resource=="calls"
        csv << parse_call_record(call)
      else
        csv << parse_sms_record(call)
      end
    end
    (1..numpages).each do |page| #iterate over remaining pages
      puts "fetching #{page}/#{numpages}..."
       if resource=="calls"
         resp = get_calls(params[:start_date],params[:end_date],PAGE_SIZE,page)
       else
         resp = get_sms(params[:start_date],params[:end_date],PAGE_SIZE,page)
       end
      resp.error! unless resp.kind_of? Net::HTTPSuccess
      pagedoc  = Nokogiri::XML(resp.body)
      calls=pagedoc.xpath(resource_xpath)
      calls.each do |call|
         if resource=="calls"
            csv << parse_call_record(call)
          else
            csv << parse_sms_record(call)
          end
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
    csv_output("calls")
  rescue
    "error validating parameters, please ensure account and auth token are correct and dates are in the format of YYYY-MM-DD and try again."
  end
end

post '/sms' do
  begin
    headers "Content-Disposition" => "attachment;filename=report.csv", "Content-Type" => "application/octet-stream"
    csv_output("sms")
  rescue
    "error validating parameters, please ensure account and auth token are correct and dates are in the format of YYYY-MM-DD and try again."
  end
end
