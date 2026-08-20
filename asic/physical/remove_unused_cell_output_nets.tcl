# Remove physically meaningless nets attached only to an unused output of a
# multi-output standard cell.
#
# Logic mapping binds every output pin of cells such as DFF_X1, HA_X1, and
# FA_X1 to an OpenDB net even when one output is unused. Those driver-only nets
# have no load and no architectural effect, but leaving them in the database
# makes repair_design attempt to repair unroutable one-pin connections. This
# hook removes only that precisely proven class before global routing.
#
# The hook fails closed if any one-pin net is a block terminal, an input pin,
# an inout pin, or belongs to an instance without another live output. Such a
# net can indicate a genuine connectivity defect and must not be discarded.

set block [ord::get_db_block]
set removable_nets {}

foreach net [$block getNets] {
    if {[$net getSigType] != "SIGNAL"} {
        continue
    }

    set iterms [$net getITerms]
    set bterms [$net getBTerms]
    set pin_count [expr {[llength $iterms] + [llength $bterms]}]

    if {$pin_count != 1} {
        continue
    }

    if {[llength $bterms] != 0} {
        error "one-pin signal net [$net getName] terminates at a block port"
    }

    set output_iterm [lindex $iterms 0]
    set output_mterm [$output_iterm getMTerm]
    if {[$output_mterm getIoType] != "OUTPUT"} {
        error "one-pin signal net [$net getName] terminates at non-output pin [[$output_iterm getInst] getName]/[$output_mterm getName]"
    }

    set instance [$output_iterm getInst]
    set live_sibling_output_count 0

    foreach sibling_iterm [$instance getITerms] {
        set sibling_mterm [$sibling_iterm getMTerm]
        if {[$sibling_mterm getIoType] != "OUTPUT"} {
            continue
        }

        set sibling_net [$sibling_iterm getNet]
        if {$sibling_net == "NULL" || $sibling_net == $net} {
            continue
        }

        set sibling_pin_count [expr {[llength [$sibling_net getITerms]] + [llength [$sibling_net getBTerms]]}]
        if {$sibling_pin_count > 1} {
            incr live_sibling_output_count
        }
    }

    if {$live_sibling_output_count == 0} {
        error "one-pin output net [$net getName] has no live sibling output on instance [$instance getName]"
    }

    lappend removable_nets [list $net $output_iterm]
}

foreach removable_net $removable_nets {
    set net [lindex $removable_net 0]
    set output_iterm [lindex $removable_net 1]

    $output_iterm disconnect
    odb::dbNet_destroy $net
}

puts "Removed [llength $removable_nets] unused multi-output-cell nets before global routing."
