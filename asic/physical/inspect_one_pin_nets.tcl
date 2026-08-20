# Inspect every one-pin signal net in an OpenDB database without changing it.
#
# Usage:
#   M64K_OPENDB=<database.odb> openroad -exit inspect_one_pin_nets.tcl

# The output is deliberately line-oriented so a host-side checker can compare
# the database contents with diagnostics emitted by the physical flow.

if {![info exists ::env(M64K_OPENDB)]} {
    error "M64K_OPENDB must name the OpenDB database to inspect"
}

read_db $::env(M64K_OPENDB)

set block [ord::get_db_block]
set one_pin_net_count 0

foreach net [$block getNets] {
    set iterms [$net getITerms]
    set bterms [$net getBTerms]
    set pin_count [expr {[llength $iterms] + [llength $bterms]}]

    if {$pin_count != 1} {
        continue
    }

    incr one_pin_net_count

    if {[llength $bterms] == 1} {
        set bterm [lindex $bterms 0]
        puts "ONE_PIN_NET net=[$net getName] kind=block_terminal terminal=[$bterm getName] direction=[$bterm getIoType]"
        continue
    }

    set iterm [lindex $iterms 0]
    set instance [$iterm getInst]
    set master [$instance getMaster]
    set mterm [$iterm getMTerm]
    set connected_output_count 0
    set unconnected_output_count 0

    foreach candidate_iterm [$instance getITerms] {
        set candidate_mterm [$candidate_iterm getMTerm]

        if {[string compare [$candidate_mterm getIoType] "OUTPUT"] != 0} {
            continue
        }

        set candidate_net [$candidate_iterm getNet]
        if {$candidate_net == "NULL"} {
            incr unconnected_output_count
            continue
        }

        set candidate_pin_count [expr {[llength [$candidate_net getITerms]] + [llength [$candidate_net getBTerms]]}]
        if {$candidate_pin_count > 1} {
            incr connected_output_count
        } else {
            incr unconnected_output_count
        }
    }

    puts "ONE_PIN_NET net=[$net getName] kind=instance_terminal instance=[$instance getName] master=[$master getName] terminal=[$mterm getName] direction=[$mterm getIoType] connected_outputs=$connected_output_count unconnected_outputs=$unconnected_output_count"
}

puts "ONE_PIN_NET_SUMMARY count=$one_pin_net_count"
