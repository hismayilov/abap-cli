class ZCL_ABAP_CLI_RESOURCE definition
  public
  inheriting from /OOP/CL_RESOURCE
  final
  create public .

public section.

  methods /OOP/IF_RESOURCE~CREATE
    redefinition .
  methods /OOP/IF_RESOURCE~READ
    redefinition .
  methods /OOP/IF_RESOURCE~UPDATE
    redefinition .
protected section.
private section.

  methods _URI_GET_RESOURCE
    importing
      !URI type STRING
    returning
      value(RETURNING) type STRING .
  type-pools ABAP .
  methods _REPORT_CHECK_VALID
    importing
      !NAME type STRING
    returning
      value(RETURNING) type ABAP_BOOL .
  methods _SAP_GET_REPORT
    importing
      !NAME type STRING
    returning
      value(RETURNING) type STRINGTAB
    exceptions
      NOT_FOUND
      CANT_READ .
  methods _SQL_GET_REPORT
    importing
      !NAME type STRING
    returning
      value(RETURNING) type ZCLI_PROGRAMS
    exceptions
      NOT_FOUND
      NO_PROGRAMS .
  methods _SQL_TO_JSON
    importing
      !PROGRAM type ZCLI_PROGRAMS
      !LINES_OF_CODE type STRINGTAB
    returning
      value(RETURNING) type ref to /OOP/IF_JSON_VALUE .
ENDCLASS.



CLASS ZCL_ABAP_CLI_RESOURCE IMPLEMENTATION.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_ABAP_CLI_RESOURCE->/OOP/IF_RESOURCE~CREATE
* +-------------------------------------------------------------------------------------------------+
* | [--->] REQUEST                        TYPE REF TO /OOP/IF_REQUEST
* | [--->] RESPONSE                       TYPE REF TO /OOP/IF_RESPONSE
* +--------------------------------------------------------------------------------------</SIGNATURE>
method /oop/if_resource~create.
"/""
"
"/"
  constants c_name     type string value 'name'.
  constants c_desc     type string value 'description'.
  constants c_loc      type string value 'loc'.
  data http_message  type string.
  data request_ct    type string.
  data program_data  type zcli_programs.
  data program_name  type string.
  data program_repid type repid.
  data description   type string.
  data lines_of_code type stringtab.
  data json_exception type ref to /oop/cx_json_parse_error.
  data json_string    type ref to /oop/cl_json_string.
  data json_array     type ref to /oop/cl_json_array.
  data json_parser    type ref to /oop/cl_json_parser.
  data json_payload   type ref to /oop/if_json_value.
  data json_object    type ref to /oop/cl_json_object.
  data json_pair      type ref to /oop/cl_json_pair.
  data json_iterator  type ref to /oop/if_iterator.
  data json_iterator2 type ref to /oop/if_iterator.
  create object json_parser.
  try.
    " First, check if the body is empty or not
    if ( request->get_body_text( ) is initial ).
      raise exception type /oop/cx_json_parse_error.
    endif.
    " Second, try to deserialize the payload
    json_payload = json_parser->deserialize( request->get_body_text( ) ).
    " Afterwards, make sure we have a json
    if ( json_payload->get_type( ) <> /oop/cl_json_types=>type_object ).
      raise exception type /oop/cx_json_parse_error.
    endif.
    " And then get the data out
    json_object ?= json_payload.
    json_iterator = json_object->iterator( ).
    while ( json_iterator->hasnext( ) = abap_true ).
      json_pair ?= json_iterator->next( ).
      case json_pair->name->value.
        when c_name.
          json_string ?= json_pair->value.
          program_name = json_string->value.
          translate program_name to upper case.
          program_repid = program_name.
        when c_desc.
          json_string ?= json_pair->value.
          description = json_string->value.
        when c_loc.
          json_array ?= json_pair->value.
          json_iterator2 = json_array->iterator( ).
          while ( json_iterator2->hasnext( ) = abap_true ).
            json_string ?= json_iterator2->next( ).
            append json_string->value to lines_of_code.
          endwhile.
      endcase.
    endwhile.
    " Program name and the lines of code are required.
    if ( program_name is initial or lines_of_code is initial ).
      message e406(ZCLI) into http_message.
      response->send_error( code = 406 message = http_message ).
      return.
    endif.
    " Check also if the program has already been used.
    select single * from zcli_programs into program_data where progname = program_repid.
    if ( sy-subrc = 0 ).
      message e409(ZCLI) into http_message.
      response->send_error( code = 409 message = http_message ).
      return.
    endif.
    " Put the program into memory
    insert report program_repid from lines_of_code.
    if ( sy-subrc = 0 ).
      data sql_program type zcli_programs.
      sql_program-progname = program_repid.
      sql_program-description = description.
      sql_program-username = sy-uname.
      sql_program-created = sy-datum.
      insert zcli_programs from sql_program.
      if ( sy-subrc <> 0 ).
        delete report program_repid.
        message e500(ZCLI) into http_message.
        response->send_error( code = 500 message = http_message ).
        return.
      endif.
    else.
      message e500(ZCLI) into http_message.
      response->send_error( code = 500 message = http_message ).
      return.
    endif.
    response->send_ok( ).
  catch /oop/cx_json_parse_error into json_exception.
    message e400(ZCLI) into http_message.
    response->send_error( code = 400 message = http_message ).
    return.
  endtry.
endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_ABAP_CLI_RESOURCE->/OOP/IF_RESOURCE~READ
* +-------------------------------------------------------------------------------------------------+
* | [--->] REQUEST                        TYPE REF TO /OOP/IF_REQUEST
* | [--->] RESPONSE                       TYPE REF TO /OOP/IF_RESPONSE
* +--------------------------------------------------------------------------------------</SIGNATURE>
method /OOP/IF_RESOURCE~READ.
  data json_output    type string.
  data json_object    type ref to /oop/if_json_value.
  data json_parser    type ref to /oop/cl_json_parser.
  data program_data   type zcli_programs.
  data lines_of_code  type stringtab.
  data resource       type string.
  data resource_valid type abap_bool.
  data http_message   type string.
  resource       = _uri_get_resource( request->get_requesturi( ) ).
  resource_valid = _report_check_valid( resource ).
  if ( resource is not initial and resource_valid = abap_true ).
    " Get the program from the database.
    call method me->_sql_get_report
      exporting name = resource
      receiving returning = program_data
     exceptions not_found = 1
                no_programs = 2.
    " Two situations, Not found or theres no data avaliable anwyay
    if ( sy-subrc = 1 ).
      message e404(ZCLI) into http_message.
      response->send_error( code = 404 message = http_message ).
      return.
    elseif ( sy-subrc = 2 ).
      message e503(ZCLI) into http_message.
      response->send_error( code = 503 message = http_message ).
      return.
    endif.
    " We need the lines of code too
    call method me->_sap_get_report
      exporting name = resource
      receiving returning = lines_of_code
     exceptions not_found = 1
                cant_read = 2.
    " Two situations, found above but not here, shits broke
    "                 or the program cannot be read permission problem.
    if ( sy-subrc = 1 ).
      message e501(ZCLI) into http_message.
      response->send_error( code = 501 message = http_message ).
      return.
    elseif ( sy-subrc = 2 ).
      message e401(ZCLI) into http_message.
      response->send_error( code = 401 message = http_message ).
      return.
    endif.
    json_object = _sql_to_json( program = program_data
                                lines_of_code = lines_of_code ).
    if ( json_object is bound ).
      create object json_parser.
      json_output = json_parser->serialize( json_object ).
      response->add_header( name = 'Content-Type' value = 'application/json' ).
      response->send_text( json_output ).
      return.
    else.
      message e500(ZCLI) into http_message.
      response->send_error( code = 500 message = http_message ).
      return.
    endif.
  else.
    message e404(ZCLI) into http_message.
    response->send_error( code = 403 message = http_message ).
    return.
  endif.
endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_ABAP_CLI_RESOURCE->/OOP/IF_RESOURCE~UPDATE
* +-------------------------------------------------------------------------------------------------+
* | [--->] REQUEST                        TYPE REF TO /OOP/IF_REQUEST
* | [--->] RESPONSE                       TYPE REF TO /OOP/IF_RESPONSE
* +--------------------------------------------------------------------------------------</SIGNATURE>
method /OOP/IF_RESOURCE~UPDATE.
  data listobject     type table of abaplist.
  data listasci       type table of char255.
  data json_output    type string.
  data json_object    type ref to /oop/if_json_value.
  data json_parser    type ref to /oop/cl_json_parser.
  data program_output type string.
  data program_data   type zcli_programs.
  data lines_of_code  type stringtab.
  data resource       type string.
  data resource_valid type abap_bool.
  data http_message   type string.
  field-symbols <asc> type char255.
  resource       = _uri_get_resource( request->get_requesturi( ) ).
  resource_valid = _report_check_valid( resource ).
  if ( resource is not initial and resource_valid = abap_true ).

    " Get the program from the database.
    call method me->_sql_get_report
      exporting name = resource
      receiving returning = program_data
     exceptions not_found = 1
                no_programs = 2.
    " Two situations, Not found or theres no data avaliable anwyay
    if ( sy-subrc = 1 ).
      message e404(ZCLI) into http_message.
      response->send_error( code = 404 message = http_message ).
      return.
    elseif ( sy-subrc = 2 ).
      message e503(ZCLI) into http_message.
      response->send_error( code = 503 message = http_message ).
      return.
    endif.

    submit (program_data-progname) exporting list to memory and return.
    call function 'LIST_FROM_MEMORY'
         tables listobject = listobject
     exceptions not_found = 1
                others = 2.
    call function 'LIST_TO_ASCI'
         tables listobject = listobject
                listasci   = listasci
     exceptions empty_list = 1
                list_index_invalid = 2
                others = 3.
    loop at listasci assigning <asc>.
      program_output = program_output && <asc> && cl_abap_char_utilities=>newline.
    endloop.
    response->send_text( program_output ).
  else.
    message e404(ZCLI) into http_message.
    response->send_error( code = 403 message = http_message ).
    return.
  endif.
endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_ABAP_CLI_RESOURCE->_REPORT_CHECK_VALID
* +-------------------------------------------------------------------------------------------------+
* | [--->] NAME                           TYPE        STRING
* | [<-()] RETURNING                      TYPE        ABAP_BOOL
* +--------------------------------------------------------------------------------------</SIGNATURE>
method _report_check_valid.
  constants start type string value 'ZCLI'.
  data length type int4.
  length = strlen( name ).
  if ( length > 40 or length = 0 ). " ABAP report names must be less than 40 char
    return.
  endif.
  if ( name cp start ). " CLI report names have to begin with ZCLI
    return.
  endif.
  returning = abap_true.
endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_ABAP_CLI_RESOURCE->_SAP_GET_REPORT
* +-------------------------------------------------------------------------------------------------+
* | [--->] NAME                           TYPE        STRING
* | [<-()] RETURNING                      TYPE        STRINGTAB
* | [EXC!] NOT_FOUND
* | [EXC!] CANT_READ
* +--------------------------------------------------------------------------------------</SIGNATURE>
method _SAP_GET_REPORT.
  data lines_of_code type table of string.
  data repid type repid.
  repid = name.
  read report repid into lines_of_code.
  if ( sy-subrc = 4 ).
    raise not_found.
  elseif ( sy-subrc = 8 ).
    raise cant_read.
  endif.
  returning = lines_of_code.
endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_ABAP_CLI_RESOURCE->_SQL_GET_REPORT
* +-------------------------------------------------------------------------------------------------+
* | [--->] NAME                           TYPE        STRING
* | [<-()] RETURNING                      TYPE        ZCLI_PROGRAMS
* | [EXC!] NOT_FOUND
* | [EXC!] NO_PROGRAMS
* +--------------------------------------------------------------------------------------</SIGNATURE>
method _SQL_GET_REPORT.
  data program type zcli_programs.
  select single * from zcli_programs into program where progname = name.
  if ( sy-subrc <> 0 ).
    raise not_found.
  endif.
  returning = program.
endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_ABAP_CLI_RESOURCE->_SQL_TO_JSON
* +-------------------------------------------------------------------------------------------------+
* | [--->] PROGRAM                        TYPE        ZCLI_PROGRAMS
* | [--->] LINES_OF_CODE                  TYPE        STRINGTAB
* | [<-()] RETURNING                      TYPE REF TO /OOP/IF_JSON_VALUE
* +--------------------------------------------------------------------------------------</SIGNATURE>
method _SQL_TO_JSON.
  data json_object       type ref to /oop/cl_json_object.
  data pair_program_name type ref to /oop/cl_json_pair.
  data pair_description  type ref to /oop/cl_json_pair.
  data pair_username     type ref to /oop/cl_json_pair.
  data pair_created      type ref to /oop/cl_json_pair.
  data pair_loc          type ref to /oop/cl_json_pair.
  data array_loc         type ref to /oop/cl_json_array.
  data string_loc        type ref to /oop/cl_json_string.
  data key               type string.
  data value             type string.
  field-symbols   <line> type string.
  if ( program is not initial ).
    key = 'name'. "name
    value = program-progname.
    pair_program_name = /oop/cl_json_util=>new_pair_with_string( name = key value = value ).
    clear: key, value.
    key = 'description'. "description
    value = program-description.
    pair_description = /oop/cl_json_util=>new_pair_with_string( name = key value = value ).
    clear: key, value.
    key = 'username'. "username
    value = program-username.
    pair_username = /oop/cl_json_util=>new_pair_with_string( name = key value = value ).
    clear: key, value.
    key = 'created'. "created
    value = program-created.
    pair_created = /oop/cl_json_util=>new_pair_with_string( name = key value = value ).
    clear: key, value.
    key = 'loc'. "loc
    create object array_loc.
    loop at lines_of_code assigning <line>.
      create object string_loc exporting value = <line>.
      array_loc->add( string_loc ).
    endloop.
    pair_loc = /oop/cl_json_util=>new_pair_with_array( name = key value = array_loc ).
    create object json_object.
    json_object->add( pair_program_name ).
    json_object->add( pair_description ).
    json_object->add( pair_username ).
    json_object->add( pair_created ).
    json_object->add( pair_loc ).
  endif.
  returning = json_object.
endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_ABAP_CLI_RESOURCE->_URI_GET_RESOURCE
* +-------------------------------------------------------------------------------------------------+
* | [--->] URI                            TYPE        STRING
* | [<-()] RETURNING                      TYPE        STRING
* +--------------------------------------------------------------------------------------</SIGNATURE>
method _URI_GET_RESOURCE.
  constants uri_split type c value '/'.
  data uri_table type stringtab.
  split uri at uri_split into table uri_table.
  read table uri_table index 3 into returning.
  translate returning to upper case.
endmethod.
ENDCLASS.
