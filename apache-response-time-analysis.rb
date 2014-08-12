#!/usr/bin/env ruby
require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'English'
require 'trollop'
require 'apache_log_regex'
require 'pony'

# http://stackoverflow.com/questions/11784843/calculate-95th-percentile-in-ruby
# http://support.microsoft.com/default.aspx?scid=kb;en-us;Q103493.
def percentile_excel(values, percentile)
    values_sorted = values.sort
    k = (percentile*(values_sorted.length-1)+1).floor - 1
    f = (percentile*(values_sorted.length-1)+1).modulo(1)
    return values_sorted[k] + (f * (values_sorted[k+1] - values_sorted[k]))
end

# Return an actual datapoint in a dataset that is at a specified percentile
def percentile_by_count(array,percentile)
  count = (array.length * (percentile)).floor
  verbose "Array entry at 95th percentile: #{count-1}"
  array.sort[count-1]
end

# FIXME: no shelling out
# Combine multiple files and return a single string variable
def filter_accesslog(accesslogpattern, filter)
  verbose "Filter being run:"
  verbose "nice gzip -cdfq #{accesslogpattern} | nice grep #{filter}"
  return `nice gzip -cdfq #{accesslogpattern} | nice grep #{filter}`
  verbose " "
end

# FIXME: no shelling out
def test_accesslogpattern(accesslogpattern)
  verbose " "
  file_matches = `ls #{accesslogpattern} 2>&1`
  if $CHILD_STATUS != 0
    puts "ls #{accesslogpattern} matched nothing"
    puts "Have you enabled the wildcard option?"
    exit
  else
    verbose "Log files matched:"
    verbose file_matches
  end
  verbose " "
end

def verbose(msg)
  puts msg if $verbose
end

def send_mail(msg,email_recipients,email_from)
  if ! email_recipients.nil?
    Pony.mail(
      :via => :sendmail,
      :from => email_from,
      :to => email_recipients,
      :subject => "Apache response time analysis",
      :body => msg
    )
  end
end

def setup_verbose(verbose_setting)
  if verbose_setting
    $verbose = true
  else
    $verbose = false
  end
end

def output_example_calculations(example_opt)
  if example_opt
    dummy_response_times = [1,2,3,4,5,6,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,100]
    puts "This is the dummy dataset:"
    p dummy_response_times
    puts "Excel method:"
    puts percentile_excel(dummy_response_times,0.95)
    puts "Count method:"
    puts percentile_by_count(dummy_response_times,0.9)
    exit
  end
end

def build_accesslog_pattern(accesslogpath_opt,datepattern_opt,wildcard_opt)
  if ! datepattern_opt.nil?
    date = Time.now.strftime(datepattern_opt)
    accesslogpattern = "#{accesslogpath_opt}*#{date}"
  else
    accesslogpattern = accesslogpath_opt
  end
  if wildcard_opt
    accesslogpattern += '*'
  end
  return accesslogpattern
end

def extract_response_times_from_apache_accesslog(accesslog_lines,logformat)
  parser = ApacheLogRegex.new(logformat)
  response_times = Array.new
  accesslog_lines.split("\n").each do | line|
    response_times.push( parser.parse(line)['%D'].to_f / 1000)
  end
  return response_times
end

def build_response_time_analysis(response_times,datepattern_opt)
  results = []
  if ! datepattern_opt.nil?
    results << "Response time results for #{Time.now.strftime(datepattern_opt)}"
  end
  results << "Total number of response times recorded:  "
  results << response_times.size.to_s
  if $verbose
    results << response_times.inspect
  end
  results << "   "
  results << "95th percentile of those values in milliseconds:  "
  results << "Excel quartile method:"
  results << percentile_excel(response_times,0.95).to_s
  results << "Count method:"
  results << percentile_by_count(response_times,0.95).to_s
  results.join("\n")
end

def display_response_time_analysis(response_time_analysis,email_recipients)
  if email_recipients.nil?
    puts response_time_analysis
  end
end

# http://trollop.rubyforge.org/trollop/Trollop/Parser.html
opts = Trollop::options do
  version "1.0"
  banner <<-EOS
  #{File.basename($0)}

  Description:
   Parse Apache compressed or uncompressed access logs and optionally filter on a string
   Extract %D    The time taken to serve the request, in microseconds.
   Find the 95th percentile figure from the range of all the values
   Output the value in milliseconds

  Dependencies:
   logformat with %D
   gzip

  Usage:
           #{File.basename($0)} [options]
  where [options] are:
  EOS
  opt :accesslogpath, "Path to accesslogs", :default => './access_log'
  opt :datepattern, "Pattern used in date e.g %Y-%m", :type => :string
  opt :wildcard, "Use a trailing wildcard?", :default => false
  opt :logformat, "Apache log format", :default => '%h %l %u %t \"%r\" %>s %b %D \"%{Referer}i\" \"%{User-Agent}i\"'
  opt :filter,    "Filter access logs based on a string", :default => '.'
  opt :verbose,    "Enable verbose mode", :default => false
  opt :example,    "Test the percentile methods with a dummy set of values", :default => false
  opt :email_recipients,    "Recipients for email output", :type => :string
  opt :email_from,    "From field for email output", :type => :string , :default => "#{ENV['USER']}@#{Socket.gethostbyname(Socket.gethostname).first}"
end
setup_verbose(opts[:verbose])

output_example_calculations(opts[:example])

# Source access logs on filesystem
accesslogpattern = build_accesslog_pattern(opts[:accesslogpath],opts[:datepattern],opts[:wildcard])
test_accesslogpattern(accesslogpattern)

# Filter the accesslogs
accesslog_lines = filter_accesslog(accesslogpattern,opts[:filter])

# Extract any log fields
response_times = extract_response_times_from_apache_accesslog(accesslog_lines,opts[:logformat])

# Build up analysis
response_time_analysis = build_response_time_analysis(response_times,opts[:datepattern])

# Optionally display the analysis on stdout
display_response_time_analysis(response_time_analysis,opts[:email_recipients])

# Optionally deliver results via email
send_mail(response_time_analysis,opts[:email_recipients],opts[:email_from])



