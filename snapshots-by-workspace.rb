#
# Barry Mullan (c) Rally Software
#
# August 2015 - Get snapshot counts per workspace in a subscription
#
# to run use ...
# ruby snapshots-by-workspace.rb <config>.json <password>
#

require 'rally_api'
require 'logger'
require 'net/http'
require 'uri'
require 'time'
require 'date'
require 'csv'
require 'pp'

class SnapshotsByWorkspace

	def	initialize(config)

		@log = Logger.new( config["log_file"] ? config["log_file"] : "log.txt" , 'daily' )

		@headers = RallyAPI::CustomHttpHeader.new()
		@headers.name = "LookBackData"
		@headers.vendor = "Rally"
		@headers.version = "1.0"

		@config = {:base_url => config["url"]} # "https://rally1.rallydev.com/slm"}
		# config[:api_key]   = config["api_key"]
		@config[:username]   = config["username"] # "xxxbmullan@emc.com"
		@config[:password]   = config["password"]
		# @config[:workspace]  = config["workspace_name"]
		@config[:version]    = "v2.0"
		# @config[:project]    = projectName #@project_name
		@config[:headers]    = @headers #from RallyAPI::CustomHttpHeader.new()

		@rally = RallyAPI::RallyRestJson.new(@config)

		@workspace = find_object(:workspace,config["workspace_name"])
		# @log.debug(@workspace)
		# @project = find_object(:project,project_name)
		# @project = find_object(:project,projectName)
		# @log.debug(projectName)
		# @log.debug(@project)
		@username = config["username"]
		@password = config["password"]

	end

	def get_all_workspaces 
		query = create_workspaces_query()
		# query.query_string = "(Name = \"#{name}\")"
		
		results = @rally.find(query)
		rally_results_to_array(results)
	end

	def find_object(type,name)
		object_query = RallyAPI::RallyQuery.new()
		object_query.type = type
		object_query.fetch = "Name,ObjectID,FormattedID,Parent,Children"
		object_query.project_scope_up = false
		object_query.project_scope_down = true
		object_query.order = "Name Asc"
		object_query.query_string = "(Name = \"" + name + "\")"
		results = @rally.find(object_query)
		results.each do |obj|
			return obj if (obj.Name.eql?(name))
		end
		nil
	end

	def get_subscription
		query = create_subscription_query()
		# query.query_string = "(Name = \"#{name}\")"
		
		results = @rally.find(query)
		rally_results_to_array(results)[0]

	end

	# "unboxes" the Rally results object into a plain ruby array
	def rally_results_to_array(results)
		arr = []
		results.each { |result|
			arr.push(result)
		}
		arr
	end

	def create_subscription_query
		iteration_query = RallyAPI::RallyQuery.new()
		iteration_query.type = :subscription
		iteration_query.workspace = nil
		iteration_query.project = nil
		iteration_query.fetch = "ObjectID,Name,State,Workspaces"
		iteration_query.project_scope_up = false
		iteration_query.project_scope_down = true
		iteration_query.order = "ObjectID"
		iteration_query.query_string = ""
		# iteration_query.limit = "Infinity"
		iteration_query
	end


	def create_workspaces_query
		iteration_query = RallyAPI::RallyQuery.new()
		iteration_query.type = :workspace
		iteration_query.workspace = nil
		iteration_query.project = nil
		iteration_query.fetch = "ObjectID,Name,State"
		iteration_query.project_scope_up = false
		iteration_query.project_scope_down = true
		iteration_query.order = "ObjectID"
		iteration_query.query_string = ""
		# iteration_query.limit = "Infinity"
		iteration_query
	end

	def lookback_query(workspace_id,body)
		# json_url = "https://rally1.rallydev.com/analytics/v2.0/service/rally/workspace/#{@workspace.ObjectID}/artifact/snapshot/query.js"
		json_url = "https://rally1.rallydev.com/analytics/v2.0/service/rally/workspace/#{workspace_id}/artifact/snapshot/query.js"
		@log.debug(json_url)
		uri = URI.parse(json_url)
		http = Net::HTTP.new(uri.host, uri.port)
		http.use_ssl = true
		http.verify_mode = OpenSSL::SSL::VERIFY_NONE
		request = Net::HTTP::Post.new(uri.request_uri,initheader = {'Content-Type' =>'application/json'})
		@log.info(body.to_json)
		request.body = body.to_json
		# @log.debug(request.body)
		request.basic_auth @username, @password
		response = http.request(request)
		@log.debug(response.code)
		# print "Response Code:'#{response.code}', #{response.code.to_i==200}\n"
		# print "Body Size:#{response.body.size}\n"
		if response.code.to_i == 200
			@log.info(response.body)
			response.body	
		else
			@log.debug("Response Code:#{response.code}")
			nil
		end
	end

	def query_snapshots_for_workspace(workspace_id)

		body = { 
			"find" => {"_ValidTo" => { "$gte" => "2015-07-01T00:00:00.000Z"} },
			"fields" => ["ObjectID"]
			# "hydrate" => ["ScheduleState"]
		}
		return lookback_query(workspace_id,body)

	end



end

def validate_args args

	#pp args

	if args.size != 2
		false
	else
		config = JSON.parse(File.read(ARGV[0]))
		config["password"] = args[1]
		config
	end


end


## check the command line arguments
config = validate_args(ARGV)

if  !config
	print "use: ruby xls-sprint-metrics.rb config.json <password>\n"
	exit
end


## create instance of our class with configuration
snapshotsMachine = SnapshotsByWorkspace.new( config )

## get the subscription object, and from it our list of workspaces
sub = snapshotsMachine.get_subscription()

ws = sub["Workspaces"]

## convert the list of workspaces to a "plain" old ruby array
workspaces = snapshotsMachine.rally_results_to_array(ws)

## this is an integrity check to check for duplicates
ids = workspaces.collect {|w| w["ObjectID"]}
uniq_ids = ids.uniq
print "Total ids:#{ids.length} Unique ids:#{uniq_ids.length}\n"


## csv header
header = ["workspace","id","state","count"]

file = config["csv_file"]
index = 0
CSV.open(file, "wb") do |csv|
	csv << header

	## get the length of the array to show in output
	len = workspaces.length
	print "Workspaces:#{len}\n"

	workspaces.each { |workspace|
		index = index + 1
		print index," of ",len,":",workspace["Name"]," [",workspace["ObjectID"],"]\n"
		begin
			## do a lbapi query for snapshots, parse the body response and display
			body = snapshotsMachine.query_snapshots_for_workspace(workspace["ObjectID"])
			jsonBody = JSON.parse(body)
			print "Count:", jsonBody["TotalResultCount"],"\n"
			csv << [workspace["Name"], workspace["ObjectID"], workspace["State"], jsonBody["TotalResultCount"]]
		rescue
			print "Failed on :",workspace["Name"]
			next
		end
	}
end


