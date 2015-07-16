require 'google/api_client'
require 'google/api_client/client_secrets'
require 'google/api_client/auth/installed_app'
require 'google/api_client/auth/storage'
require 'google/api_client/auth/storages/file_store'
require 'fileutils'
require 'optparse'

trap "SIGINT" do
  puts "Exiting"
  exit 1
end

$options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: gdelete.rb [options]"

  opts.on('-q', '--query QUERY', 'Query string') { |v| $options[:query] = v }
  opts.on('-f', '--no-from', 'Allow no from filter') { $options[:no_from] = true }
  opts.on('-b', '--no-before', 'Allow no before filter') { $options[:no_before] = true }

end.parse!

APPLICATION_NAME = 'gdelete'
CLIENT_SECRETS_PATH = 'client_secret.json'
CREDENTIALS_PATH = File.join(Dir.home, '.credentials',
                             "gmail-gdelete.json")
SCOPE = 'https://www.googleapis.com/auth/gmail.modify'

##
# Ensure valid credentials, either by restoring from the saved credentials
# files or intitiating an OAuth2 authorization request via InstalledAppFlow.
# If authorization is required, the user's default browser will be launched
# to approve the request.
#
# @return [Signet::OAuth2::Client] OAuth2 credentials
def authorize
  FileUtils.mkdir_p(File.dirname(CREDENTIALS_PATH))

  file_store = Google::APIClient::FileStore.new(CREDENTIALS_PATH)
  storage = Google::APIClient::Storage.new(file_store)
  auth = storage.authorize

  if auth.nil? || (auth.expired? && auth.refresh_token.nil?)
    app_info = Google::APIClient::ClientSecrets.load(CLIENT_SECRETS_PATH)
    flow = Google::APIClient::InstalledAppFlow.new({
      :client_id => app_info.client_id,
      :client_secret => app_info.client_secret,
      :scope => SCOPE})
    auth = flow.authorize(storage)
    puts "Credentials saved to #{CREDENTIALS_PATH}" unless auth.nil?
  end
  auth
end

# Initialize the API
$client = Google::APIClient.new(:application_name => APPLICATION_NAME)
$client.authorization = authorize
$gmail_api = $client.discovered_api('gmail', 'v1')

def fetch_more_messages
  results = $client.execute!(
    :api_method => $gmail_api.users.messages.list,
    :parameters => { :userId => 'me',
                     :q => $options[:query],
                     :maxResults => 100,
                     :pageToken => $next_page_token,
                     :fields => "messages/id,nextPageToken,resultSizeEstimate" }
  )
  puts "Fetching messages to delete.  Params: #{results.request.parameters}"
  $next_page_token = results.data.next_page_token
  results.data
end

# Make sure the query string contains a from filter unless --no-from
if !$options[:no_from] && $options[:query] !~ /\bfrom:/
  puts "The query must contain a from: filter for safety (you might cautiously use --no-from)"
  exit 1
end

# Make sure the query string contains a before filter unless --no-before
if !$options[:no_before] && $options[:query] !~ /\bbefore:/
  puts "The query must contain a before: filter for safety (you might cautiously use --no-before)"
  exit 1
end

# Use the query string to announce how many emails will be deleted
puts "Google's estimate is that #{fetch_more_messages.result_size_estimate} match this query."
puts "Are you sure you want to delete all of these? 'y' to continue"
exit 1 unless gets.strip == "y"

total_deleted = 0
until (fetched_messages = fetch_more_messages.messages).empty?
  # delete in batches of 1000 (limit of requests in a batch)
  until fetched_messages.empty?
    batch = Google::APIClient::BatchRequest.new() do |result|
      if result.status == 200
        total_deleted += 1
      else
        puts "#{result.request.parameters} => #{result.status}"
      end
    end

    batched_request_count = 0
    fetched_messages.shift(15).each do |m|
      batch.add(:api_method => $gmail_api.users.messages.trash, :parameters => { :userId => 'me', :id => m.id })
      batched_request_count += 1
    end
    $client.execute!(batch)
    puts "Total deleted #{total_deleted}"
  end
end

puts "All done."
