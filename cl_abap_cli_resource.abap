"/""
" The code is saved in REPOSRC and is base64 encoded LZ78 compressed string
" The keyword INSERT, SUBMIT, and DELETE seem to work fine too.
"/
class cl_abap_cli_resource definition
  public inheriting from /oop/cl_resource final create public.
  public section.
    methods /oop/if_resource~create redefinition.
endclass.

class cl_abap_cli_resource implementation.
  method /oop/if_resource~create.
    " The ABAP output has to be captured from memory, in these datatypes I guess.
    data list_obj type table of abaplist.
    data list_asc type table of char255.
    data report_name type sy-repid.
    " I create a GUID so that each ABAP launch will have a unique identifier.
    data guid16 type guid_16.
    data guid22 type guid_22.
    data guid32 type guid_32.
    call function 'GUID_CREATE'
      importing
        ev_guid_16 = guid16
        ev_guid_22 = guid22
        ev_guid_32 = guid32.
    guid22 = 'z' && guid22.
    translate guid22 to upper case.
    report_name = guid22.
    data abap_code_flat type string.
    data abap_code_table type stringtab.
    field-symbols <asc> type char255.
    field-symbols <abap> type string.
    data program_output type string.
    " The incoming code is placed straight in the HTTP response body and broken up
    " into a SAP internal table.
    abap_code_flat = request->get_body_text( ).
    split abap_code_flat at cl_abap_char_utilities=>newline into table abap_code_table.
    loop at abap_code_table assigning <abap>.
      data line_length type i.
      data last_character type c.
      line_length = STRLEN( <abap> ).
      line_length = line_length - 1.
      last_character = <abap>+line_length(1).
      <abap> = <abap>+0(line_length).
    endloop.
    if ( abap_code_flat is initial ).
      response->send_error( code = 400 message = 'Missing ABAP code.' ).
    endif.
    " A temp report using a generated GUID is created which contains the code from the http request
    " The report is submitted and the execution is exported to memory
    " The report is deleted afterwards.
    insert report guid22 from abap_code_table.
    submit (guid22) exporting list to memory and return.
    delete report guid22.
    " The output from the execution (WRITE statements) is captured and looped across
    " and placed in the body of the response to be returned to the caller.
    call function 'LIST_FROM_MEMORY'
      tables
        listobject = list_obj
      exceptions
        not_found  = 1
        others     = 2.
    call function 'LIST_TO_ASCI'
      tables
        listasci           = list_asc
        listobject         = list_obj
      exceptions
        empty_list         = 1
        list_index_invalid = 2
        others             = 3.
    loop at list_asc assigning <asc>.
      program_output = program_output && <asc> && cl_abap_char_utilities=>newline.
    endloop.
    response->send_text( program_output ).
  endmethod.
endclass.