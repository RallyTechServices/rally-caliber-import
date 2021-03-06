require 'base64'
require 'csv'
require 'nokogiri'
require 'uri'
require 'rally_api'
require 'logger'
require './caliber_helper.rb'
require './multi_io.rb'

# Rally Connection parameters
$my_base_url                     = "https://rally1.rallydev.com/slm"
$my_username                     = "user@company.com"
$my_password                     = "topsecret"
$wsapi_version                   = "1.43"
$my_workspace                    = "Caliber"
$my_project                      = "Scratch"
$max_attachment_length           = 5000000

# Caliber parameters
$caliber_file_name               = "hhc.xml"
$caliber_id_field_name           = 'CaliberID'
$caliber_image_directory         = "/images"

# Runtime preferences
$max_import_count                = 100000
$html_mode                       = true
$preview_mode                    = false

# Flag to set in @rally_story_hierarchy_hash if Requirement has no Parent
$no_parent_id                    = "-9999"

# Output parameters
$my_output_file                  = "caliber_requirements.csv"
$requirement_fields              =  %w{id hierarchy name project description validation purpose pre_condition basic_course post_condition exceptions remarks}

# Output fields to store a CSV
# allowing lookup of TestCase OID by Caliber TestCase ID
# (needed for traces import)
$story_oid_output_csv            = "story_oids_by_testcaseid.csv"
$story_oid_output_fields         =  %w{reqname ObjectID}

# JDF Project setting
$caliber_project                 = "JDF-Zeus_Control-project"
$jdf_zeus_control_project        = "JDF-Zeus_Control-project"

if $my_delim == nil then $my_delim = "\t" end

# Load (and maybe override with) my personal/private variables from a file...
# my_vars = File.dirname(__FILE__) + "/my_vars_requirements.rb"
# if FileTest.exist?( my_vars ) then require my_vars end

# HTML Mode vs. XML Mode
# The following is needed to preserve newlines in formatting of UDAValues when
# Imported into Rally. Caliber export uses newlines in UDAValue attributes as formatting.
# When importing straight XML, the newlines are ignored completely
# Rally (and Nokogiri, really) needs markup. This step replaces newlines with <br>
# And reads the resulting input as HTML rather than XML
caliber_file = File.open($caliber_file_name, 'rb')
caliber_content = caliber_file.read
caliber_content_html = caliber_content.gsub("\n", "&lt;br&gt;\n")

if $html_mode then
    caliber_data = Nokogiri::HTML(caliber_content_html, 'UTF-8') do | config |
        config.strict
    end
else
    caliber_data = Nokogiri::XML(File.open($caliber_file_name), 'UTF-8') do | config |
        config.strict
    end
end

# set preview mode
if $preview_mode then
    $import_to_rally                 = false
    $stitch_hierarchy                = false
    $import_images_flag              = false
else
    $import_to_rally                 = true
    $stitch_hierarchy                = true
    $import_images_flag              = true
end

# The following are all value attributes inside the <Requirement> tag itself.
# Example:
# <Requirement
#      index="0"
#      hierarchy="1"
#      id="20023"
#      name="Operating harvester head"
#      description="&lt;html&gt;&lt;body&gt;&lt;/html&gt;"
#      validation=""
#      type="JDF Requirement (REQ)"
#      owner=""
#      status="Submitted"
#      priority="Essential"
#      version="1.12"
#      tag="REQ20023"
#      name_tag="Operating harvester headREQ20023">

# Tags of interest
$report_tag                              = "Report"
$requirement_type_tag                    = "ReqType"
$requirement_tag                         = "Requirement"
$uda_values_tag                          = "UDAValues"
$uda_value_tag                           = "UDAValue"

# These are the value tags to look/parse for once on the <Requirement> tag
$requirement_name                        = "name"
$requirement_hierarchy                   = "hierarchy"
$requirement_id                          = "id"
$requirement_validation                  = "validation"

# In HTML mode, the tags are all lowercase so downcase them
if $html_mode then
    $report_tag                          = $report_tag.downcase
    $requirement_type_tag                = $requirement_type_tag.downcase
    $requirement_tag                     = $requirement_tag.downcase
    $uda_values_tag                      = $uda_values_tag.downcase
    $uda_value_tag                       = $uda_value_tag.downcase
end

# The following are all types of <UDAValue> records on <Requirement>
# Example:

# <UDAValue id="4241" req_id="20023" name="JDF Purpose [Pu]" value="This is not a requirement but a chapter title."/>
# <UDAValue id="4242" req_id="20023" name="JDF Basic Course [Ba]" value="Operating harvester head involves
# - closing harvester head
# - opening harvester head
# "/>
# <UDAValue id="4243" req_id="20023" name="JDF Post-condition [Po]" value="None."/>
# <UDAValue id="4244" req_id="20023" name="JDF Exceptions [Ex]" value="None."/>
# <UDAValue id="4245" req_id="20023" name="JDF Machine Type" value="Harvester"/>
# <UDAValue id="4246" req_id="20023" name="JDF Input [In]" value="None."/>
# <UDAValue id="4247" req_id="20023" name="JDF Project" value="5.0"/>
# <UDAValue id="4248" req_id="20023" name="JDF Content Status" value="5. Approved"/>
# <UDAValue id="4249" req_id="20023" name="JDF Delivery Status" value="UNDEFINED"/>
# <UDAValue id="4250" req_id="20023" name="JDF Output [Ou]" value="None."/>
# <UDAValue id="4251" req_id="20023" name="JDF Open Issues" value=""/>
# <UDAValue id="4252" req_id="20023" name="JDF Remarks [Re]" value="None."/>
# <UDAValue id="4253" req_id="20023" name="JDF Requirement Class" value="High level"/>
# <UDAValue id="4254" req_id="20023" name="JDF Source [So]" value="PAi &amp; Ilari V"/>
# <UDAValue id="4255" req_id="20023" name="JDF Pre-condition [Pr]" value="None."/>
# <UDAValue id="4256" req_id="20023" name="JDF Software Load" value="3"/>
# </UDAValues>

# These are the value fields to look/parse for once on the <UDAValues> tag
$uda_value_name_purpose                  = "JDF Purpose [Pu]"
$uda_value_name_pre_condition            = "JDF Pre-condition [Pr]"
$uda_value_name_basic_course             = "JDF Basic Course [Ba]"
$uda_value_name_post_condition           = "JDF Post-condition [Po]"
$uda_value_name_exceptions               = "JDF Exceptions [Ex]"
$uda_value_name_remarks                  = "JDF Remarks [Re]"
$uda_value_name_open_issues              = "JDF Open Issues"


# Record template hash for a requirement from Caliber
# Hash fields are in same order as CSV output format

$caliber_requirement_record_template = {
    'id'                    => 0,
    'hierarchy'             => 0,
    'name'                  => "",
    'project'               => "",
    'description'           => "",
    'caliber_validation'    => "",
    'caliber_purpose'       => "",
    'pre_condition'         => "",
    'basic_course'          => "",
    'post_condition'        => "",
    'exceptions'            => "",
    'remarks'               => "",
    'open_issues'           => ""
}

$description_field_hash = {
    'Caliber Purpose'         => 'caliber_purpose',
    'Pre-condition'           => 'pre_condition',
    'Basic course'            => 'basic_course',
    'Post-condition'          => 'post_condition',
    'Exceptions'              => 'exceptions',
    'Remarks'                 => 'remarks',
    'Description'             => 'description'
}


begin

#==================== Connect to Rally and Import Caliber data ====================

    #Setting custom headers
    $headers                            = RallyAPI::CustomHttpHeader.new()
    $headers.name                       = "Caliber Requirement Importer"
    $headers.vendor                     = "Rally Technical Services"
    $headers.version                    = "0.50"

    config                  = {:base_url => $my_base_url}
    config[:username]       = $my_username
    config[:password]       = $my_password
    config[:workspace]      = $my_workspace
    config[:project]        = $my_project
    config[:version]        = $wsapi_version
    config[:headers]        = $headers

    @rally = RallyAPI::RallyRestJson.new(config)
    puts @rally.url
    exit

    # Instantiate Logger
    log_file = File.open("caliber2rally.log", "a")
    log_file.sync = true
    @logger = Logger.new MultiIO.new(STDOUT, log_file)

    @logger.level = Logger::INFO #DEBUG | INFO | WARNING | FATAL

    # Initialize Caliber Helper
    @caliber_helper = CaliberHelper.new(@rally, $caliber_project, $caliber_id_field_name,
        $description_field_hash, $caliber_image_directory, @logger, nil)

    # Output CSV of Requirement data
    requirements_csv = CSV.open($my_output_file, "wb", {:col_sep => $my_delim})
    requirements_csv << $requirement_fields

    # Output CSV of Story OID's by Caliber Requirement Name
    story_oid_csv    = CSV.open($story_oid_output_csv, "wb", {:col_sep => $my_delim})
    story_oid_csv    << $story_oid_output_fields

    # The following are used for the post-run stitching
    # Hash of User Stories keyed by Caliber Requirement Hierarchy ID
    @rally_story_hierarchy_hash = {}

    # The following are used for the post-run import of images for
    # Caliber requirements whose description contains embedded images
    @rally_stories_with_images_hash = {}

    # Hash of Requirement Parent Hierarchy ID's keyed by Self Hierarchy ID
    @caliber_parent_hash = {}

    # Read through caliber file and store requirement records in array of requirement hashes
    import_count = 0
    caliber_data.search($report_tag).each do | report |
        report.search($requirement_type_tag).each do | req_type |
            req_type.search($requirement_tag).each do | requirement |

                # Data - holds output for CSV
                requirement_data = []
                story_oid_data         = []

                # Store fields that derive from Project and Requirement objects
                this_requirement = $caliber_requirement_record_template
                this_requirement['project']             = report['project']
                this_requirement['hierarchy']           = requirement['hierarchy']
                this_requirement['id']                  = requirement['id']
                this_requirement['name']                = requirement['name'] || ""

                # process_description_body pulls HTML content out of <html><body> tags
                this_requirement['description']         = @caliber_helper.process_description_body(requirement['description'] || "")
                this_requirement['validation']          = requirement['validation'] || ""

                # Store Caliber ID, HierarchyID, Project and Name in variables for convenient logging output
                req_id                                  = this_requirement['id']
                req_hierarchy                           = this_requirement['hierarchy']
                req_project                             = this_requirement['project']
                req_name                                = this_requirement['name']

                @logger.info "Started Reading Caliber Requirement ID: #{req_id}; Hierarchy: #{req_hierarchy}; Project: #{req_project}"

                # Loop through UDAValue records and cache fields from them
                # There are many UDAValue records per requirement and each is different
                # So assign to values of interest via case statement
                requirement.search($uda_values_tag).each do | uda_values |
                    uda_values.search($uda_value_tag).each do | uda_value |
                        uda_value_name = uda_value['name']
                        uda_value_value = uda_value['value'] || ""
                        case uda_value_name
                            when $uda_value_name_purpose
                                this_requirement['caliber_purpose']    = uda_value_value
                            when $uda_value_name_pre_condition
                                this_requirement['pre_condition']      = uda_value_value
                            when $uda_value_name_basic_course
                                this_requirement['basic_course']       = uda_value_value
                            when $uda_value_name_post_condition
                                this_requirement['post_condition']     = uda_value_value
                            when $uda_value_name_exceptions
                                this_requirement['exceptions']         = uda_value_value
                            when $uda_value_name_remarks
                                this_requirement['remarks']            = uda_value_value
                            when $uda_value_name_open_issues
                                this_requirement['open_issues']        = uda_value_value
                        end
                    end
                end

                @logger.info "Finished Reading Caliber Requirement ID: #{req_id}; Hierarchy: #{req_hierarchy}; Project: #{req_project}"

                # Dummy story used only when testing
                story = {
                    "ObjectID"       => 12345678910,
                    "FormattedID"    => "US1234",
                    "Name"           => "My Story",
                    "Description"    => "My Description",
                    "_ref"           => "/hierarchicalrequirement/12345678910"
                }

                # Import to Rally
                if $import_to_rally then
                    story = @caliber_helper.create_story_from_caliber(this_requirement)
                end

                # Save the Story OID and associated it to the Caliber Hierarchy ID for later use
                # in stitching
                @rally_story_hierarchy_hash[req_hierarchy] = story

                # Get the Parent hierarchy ID for this Caliber Requirement
                parent_hierarchy_id = @caliber_helper.get_parent_hierarchy_id(this_requirement)
                @logger.info "Parent Hierarchy ID: #{parent_hierarchy_id}"

                # Store the requirements Parent Hierarchy ID for use in stitching
                @caliber_parent_hash[req_hierarchy] = parent_hierarchy_id

                # store a hash containing:
                # - Caliber description field
                # - Array of caliber image file objects in Story hash
                #
                # For later use in post-processing run to import images
                # This allows us to import the images onto Rally stories by OID, and
                # Update the Rally Story Description-embedded images that have Caliber
                # file URL attributes <img src="file:\\..." with a new src with a relative URL
                # to a Rally attachment, once created

                # Count embedded images inside Caliber description
                caliber_image_count = @caliber_helper.count_images_in_caliber_description(this_requirement['description'])

                if caliber_image_count > 0 then
                    description_with_images = this_requirement['description']
                    image_file_objects, image_file_ids = @caliber_helper.get_caliber_image_files(description_with_images)
                    caliber_image_data = {
                        "files"           => image_file_objects,
                        "ids"             => image_file_ids,
                        "description"     => description_with_images,
                        "ref"        => story["_ref"]
                    }
                    @rally_stories_with_images_hash[story["ObjectID"].to_s] = caliber_image_data
                end

                # Record requirement data for CSV output
                this_requirement.each_pair do | key, value |
                    requirement_data << value
                end

                # Post-pend to CSV
                requirements_csv << CSV::Row.new($requirement_fields, requirement_data)

                # Output story OID and Caliber requirement name
                # So we can use this information later when importing traces
                story_oid_data << req_name
                story_oid_data << story["ObjectID"]
                # Post-pend to CSV
                story_oid_csv  << CSV::Row.new($story_oid_output_fields, story_oid_data)

                # Circuit-breaker for testing purposes
                if import_count < $max_import_count then
                    import_count += 1
                else
                    break
                end
            end
        end
    end

    # Only import into Rally if we're not in "preview_mode" for testing
    if $preview_mode then
        @logger.info "Finished Processing Caliber Requirements for import to Rally. Total Stories Processed: #{import_count}."
    else
        @logger.info "Finished Importing Caliber Requirements to Rally. Total Stories Created: #{import_count}."
    end

    # Run the hierarchy stitching service
    if $stitch_hierarchy then
        @caliber_helper.post_import_hierarchy_stitch(@caliber_parent_hash,
            @rally_story_hierarchy_hash)
    end

    # Run the image import service
    # Necessary to run the image import as a post-Story creation service
    # Because we have to have an Artifact in Rally to attach _to_.
    if $import_images_flag
        @caliber_helper.import_images(@rally_stories_with_images_hash)
    end
end