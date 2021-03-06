# Reference on contents of `test-cases.json` file

## Key `log_file_id`

The `"log_file_id"` key has an associated integer value, which is the
number used in lines like the ones shown below in the output of
`p4pktgen`:

```
INFO: BEGIN 1 Exp path (len 3+0=3) complete_path False: ['start', u'parse_ipv4', 'sink']
[ ... many lines of output between these two lines omitted for brevity ... ]
INFO: END   1 Exp path (len 3+0=3) complete_path False TestPathResult.SUCCESS: ['start', u'parse_ipv4', 'sink']
```

This value is there so that you may more quickly find the section of
`p4pktgen` output corresponding to this test case, in the event you
want more details about what `p4pktgen` was doing when it analyzed
this test case.


## Key `result`

The associated value is a string, with one of these values:

* `SUCCESS` - A packet and table entries were found that cause this
  path through the code to be executed, and running it through
  `simple_switch` matched the expected execution path, according to
  the debug log output of that program.

* `TEST_FAILED` - Similar to `SUCCESS`, except that when the table
  entries were installed and the packet sent in, `simple_switch` had a
  different execution path than the expected one.  This could be due
  to a bug in `p4pktgen`, `p4c-bm2-ss`, or `simple_switch`, or it
  could be due to a P4 program that `p4pktgen` either cannot predict
  what the execution path will be, or not control it from the inputs
  (e.g. because a random number is generated during `simple_switch`
  execution, and the resulting value affects the execution flow).

* `NO_PACKET_FOUND` - No combination of packet and table entries was
  found by `p4pktgen` that could cause this path through the code to
  be executed.  For example, if the parser extracted an IPv4 header,
  and later the program has an `if` statement that checks the
  condition `hdr.ipv4.isValid()`, taking the false branch of that `if`
  statement would be impossible if nothing had changed the validity of
  that header before the `if` statement was executed.

* `UNINITIALIZED_READ` - An execution path was analyzed such that at
  some point the value of a header or metadata field is used in an
  expression or table search key, and that field has not been
  initialized before.  This result is only possible if you do not use
  the command line option `--allow-uninitialized-reads`.

* `INVALID_HEADER_WRITE` - An execution path was analyzed such that at
  some point there is an assignment to a field in a header, while that
  header is invalid.  This result is only possible if you do not use
  the command line option `--allow-invalid-header-writes`.

* `PACKET_SHORTER_THAN_MIN` - A packet and table entries were found,
  but the packet was shorter than the minimum length packet allowed.
  The default minimum length is 14 bytes, but `p4pktgen` will likely
  be enhanced to allow shorter packets to be generated.


## Key `expected_path`

The associated value is a list of strings, representing the expected
path of control flow through the program that `p4pktgen` was trying to
exercise with this test case.

It always begins with `"start"`, representing the start state of the
parser.  There can be one or more parser state names that follow this
start state, ending with `"sink"`, which represents the parser
finishing, regardless of whether it finished with a parser error or
not.

The control flow through the ingress control block are represented by
a sequence of strings, each of one of the following forms:

* `('table_name', 'action_name')` - The table with the given name was
  applied, and matched a table entry for which the control plane
  installed an action with the given name.
* `('node_name', (True/False, ('filename', line_number,
  'source_code_fragment')))` - The node_name is a string generated by
  the P4 compiler `p4c-bm2-ss` to name a "condition node" in the bmv2
  JSON file, at which the condition in an `if` statement is evaluated,
  and either the True or False branch will be executed next.
  True/False represents the expected value of this condition for this
  path.  The filename, line_number, and source_code_fragment indicate
  where in the P4 source code this condition comes from, and at least
  the first line of the source code of the condition.


## Key `complete_path`

The associated value is `true` if this path represents a complete flow
of execution from the start of parsing to the end of the ingress
control block.  It can be `false` for partial execution paths that end
before the end of the ingress control block is reached.  For example,
a test case can have a partial execution path if it has a result of
`NO_PACKET_FOUND`, if `p4pktgen` determined that this partial path
cannot have any packet that causes it to occur.  `p4pktgen` uses this
as an opportunity to avoid examining any longer execution paths
beginning with the same sequence, since they must also be impossible
to find a packet that makes them occur.


## Keys `ss_cli_setup_cmds` and `table_setup_cmd_data`

`ss` is an abbreviation of `simple_switch`, and this key can be read
as "simple_switch CLI setup commands".  It is an array of strings,
each of which is a command in a syntax that is accepted by the program
`simple_switch_CLI`.  Currently `p4pktgen` only creates `table_add` or
`table_set_default` commands, but it may be enhanced in the future to
create other commands accepted by `simple_switch_CLI`, e.g. commands
for creation action selector groups and members, for programs that use
action selectors.

The value will be an empty array if `result` is `NO_PACKET_FOUND`.

The value associated with the key `table_setup_cmd_data` is an array
of objects, where each object contains further key/value pairs that
describe a `simple_switch_CLI` command.  It contains exactly the same
information as `ss_cli_setup_cmds` does, but broken down into its
pieces as a data structure.  This should make it straightforward to
construct P4 API control plane calls from this data, without having to
parse or otherwise break apart the contents of the strings in
`ss_cli_setup_cmds`.


## Key `input_packets`

The associated value is an array of objects, one for each input
packet.  As `p4pktgen` is currently written, there will be at most one
packet, but the data structure is defined to make it easy to extend to
any number of input packets, in case that becomes useful in the
future.

Each object contains the keys `port`, `packet_hexstr`, and
`packet_len_bytes`.  The value of `port` is an integer indicating the
number of the port that packet should be sent into.  The value of
`packet_hexstr` is a string containing an even number of hexadecimal
digits, representing some whole number of bytes, or octets, of the
contents of the packet to send to the device.  The value of
`packet_len_bytes` is redundant given the value of `packet_hexstr`,
since it is simply the integer value that is the number of bytes in
the packet.  It is included for the convenience of people reading the
data.

The value will be an empty array if `result` is `NO_PACKET_FOUND`.


## Keys `parser_path_len` and `ingress_path_len`

The values of these keys are integers.  They are simply counts of the
number of elements in the portions of the `expected_path`
corresponding to the parser, and the ingress control block.

They are thus redundant data given the value of `expected_path`, and
are included solely for the convenience of people reading the data.


## Keys `uninitialized_read_data` and `invalid_header_write_data`

The key `uninitialized_read_data` is only present if `result` is
`UNINITIALIZED_READ`.

Its associated value is an array of objects, one object for each
header or metadata field found to be read before it is initialized in
this path of execution.  Each object has a key `variable_name` with
associated value being a string containing the field name.  It also
has a key `source_info` with an associated value being an object
containing keys `filename`, `line`, `column`, and `source_fragment`,
indicating the location in the P4 program where the uninitialized read
occurred.  For fields that are search keys of tables, the
`source_info` may indicate the location of the name of the table,
rather than precisely the location where the key field is defined.

The key `invalid_header_write_data` is only present if `result` is
`INVALID_HEADER_WRITE`.  It is similar to `uninitialized_read_data`,
except it is a list of objects, one for each header field found to be
assigned to, when the header is invalid.


## Key `actual_path_data`

The key `actual_path_data` is only present if `result` is
`TEST_FAILED`.

Its associated value is the same format as that of `expected_path`,
except that it describes the actual execution path taken by
`simple_switch` while processing the packet, when it differs in some
way from `expected_path`.
