# Rally Connection parameters
$my_base_url                     = "https://rally1.rallydev.com/slm"
$my_username                     = "user@company.com"
$my_password                     = "topsecret"
$wsapi_version                   = "1.43"
$my_workspace                    = "My Workspace"
$my_project                      = "My Project"
$max_attachment_length           = 5000000

# Caliber parameters
$caliber_file_name               = "hhc_traces.xml"
$caliber_trace_field_name        = 'CaliberTraces'

# Cached Caliber Requirement to Rally Story OID data
$story_oids_from_reqname         = "story_oids_by_reqname.csv"

# Runtime preferences
$max_import_count                = 100000
$preview_mode                    = false

# JDF Project setting
$jdf_zeus_control_project        = "JDF-Zeus_Control-project"

if $my_delim == nil then $my_delim = "\t" end