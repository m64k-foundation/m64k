# Report high-fanout signal-net topology from an OpenDB database without
# changing it. M64K_HIGH_FANOUT_THRESHOLD defaults to 100 terminals.

if {![info exists ::env(M64K_OPENDB)]} {
    error "M64K_OPENDB must name the OpenDB database to inspect"
}

if {[info exists ::env(M64K_HIGH_FANOUT_THRESHOLD)]} {
    set fanout_threshold $::env(M64K_HIGH_FANOUT_THRESHOLD)
} else {
    set fanout_threshold 100
}

read_db $::env(M64K_OPENDB)

set block [ord::get_db_block]
set high_fanout_net_count 0

foreach net [$block getNets] {
    if {[$net getSigType] != "SIGNAL"} {
        continue
    }

    set iterms [$net getITerms]
    set bterms [$net getBTerms]
    set terminal_count [expr {[llength $iterms] + [llength $bterms]}]
    if {$terminal_count <= $fanout_threshold} {
        continue
    }

    incr high_fanout_net_count
    set driver_description "none"
    set load_count 0

    foreach iterm $iterms {
        set mterm [$iterm getMTerm]
        set direction [$mterm getIoType]

        if {$direction == "OUTPUT"} {
            set instance [$iterm getInst]
            set driver_description "instance=[$instance getName] master=[[$instance getMaster] getName] terminal=[$mterm getName]"
        } else {
            incr load_count
        }
    }

    foreach bterm $bterms {
        if {[$bterm getIoType] == "INPUT"} {
            set driver_description "block_terminal=[$bterm getName]"
        } else {
            incr load_count
        }
    }

    puts "HIGH_FANOUT_NET net=[$net getName] terminals=$terminal_count loads=$load_count driver={$driver_description}"
}

puts "HIGH_FANOUT_NET_SUMMARY threshold=$fanout_threshold count=$high_fanout_net_count"
