#!/usr/bin/env python3
import argparse
import os
import sys
from time import sleep

import grpc

# Import P4Runtime lib from parent utils dir
import utils.p4runtime_lib.bmv2 as bmv2
import utils.p4runtime_lib.helper as helper
from utils.p4runtime_lib.error_utils import printGrpcError
from utils.p4runtime_lib.switch import ShutdownAllSwitchConnections

ENABLED_PORT  = [1,2,3,4]
TIMEOUT_SEC = 15

def main(p4info_file_path, bmv2_file_path, routing_info):
    # Instantiate a P4Runtime helper from the p4info file
    p4info_helper = helper.P4InfoHelper(p4info_file_path)

    try:
        # Create a switch connection object for s1 and s2;
        # this is backed by a P4Runtime gRPC connection.
        # Also, dump all P4Runtime messages sent to switch to given txt files.
        s1 = bmv2.Bmv2SwitchConnection(
            name='s1',
            address='127.0.0.1:50051',
            device_id=0,
            #proto_dump_file='/logs/s1-p4runtime-requests.txt'
        )

        def print_table_entries(table_name: str):
            print ("-"*64)
            print ("Table Entries of", table_name)
            print ("match_field: value | action | action_param: value")
            
            table_id = p4info_helper.get_tables_id(table_name)
            for response in s1.ReadTableEntries(table_id):
                for entity in response.entities:
                    #print(dir(entity.table_entry.match))
                    table_entry = entity.table_entry
                    for match in table_entry.match:
                        match_id = match.field_id
                        match_name = p4info_helper.get_match_field_name(
                            table_name=table_name,
                            match_field_id=match_id
                        )            
                        match_val = match.exact.value
                        print(f"{match_name}:{match_val.hex()}", end=" ")
                    
                    action_id = table_entry.action.action.action_id
                    action_name = p4info_helper.get_actions_name(action_id)
                    print(f"| {action_name} |", end=" ") 
                    for param in table_entry.action.action.params:
                        param_id = param.param_id
                        param_val = param.value
                        param_name = p4info_helper.get_action_param_name(action_name, param_id)
                        print(f"{param_name}:{param_val.hex()}", end=" ")
                    print()
            print ("-"*64)

        # Send master arbitration update message to establish this controller as
        # master (required by P4Runtime before performing any other write operation)
        s1.MasterArbitrationUpdate()
        s1.SetForwardingPipelineConfig(p4info=p4info_helper.p4info,
                                   bmv2_json_file_path=bmv2_file_path)
        print ("Installed P4 Program using SetForwardingPipelineConfig on %s" % s1.name)
        
        # Add static routing table and arp table
        with open(routing_info, 'r') as f:
            for line in f:
                ip_mac_pair = line.split(',')
                prefix, prefix_len = ip_mac_pair[0].split('/')
                next_hop_ip = ip_mac_pair[1]
                next_hop_mac = ip_mac_pair[2]
                egress_mac = ip_mac_pair[3]
                egress_port = int(ip_mac_pair[4].strip('\n'))
                prefix_len = int(prefix_len)

                print ("Add routing table entry", prefix, prefix_len, next_hop_ip)
                # TODO: Add table entries to "MyIngress.ipv4_route"
                # They represent the prefix of dstIP to next hop IP mapping.
                # 1. Use p4info_helper's buildTableEntry() method to build a table_entry
                # 2. Add the table_entry to the switch by calling s1's WriteTableEntry() method
                ipv4_route_entry = p4info_helper.buildTableEntry(
                    table_name="MyIngress.ipv4_route",
                    match_fields={"hdr.ipv4.dest_addr": [prefix, prefix_len]},
                    # match_fields={"hdr.ipv4.dest_addr": {
                    #     "value": prefix,
                    #     "prefix_len": prefix_len
                    # }},
                    action_name="MyIngress.forward_to_next_hop",
                    action_params={"next_hop": next_hop_ip}
                )
                # Add the table entry to the switch
                s1.WriteTableEntry(ipv4_route_entry)

                print("wrote to ipv4")

                
                print ("Add ARP table entry", next_hop_ip, next_hop_mac)
                # TODO: Add table entries to "MyIngress.arp_table"
                # They represent the next hop IP to dstMAC mapping.
                # 1. Use p4info_helper's buildTableEntry() method to build a table_entry
                # 2. Add the table_entry to the switch by calling s1's WriteTableEntry() method
                # Build table entry for ARP table
                arp_entry = p4info_helper.buildTableEntry(
                    table_name="MyIngress.arp_table",
                    match_fields={"meta.next_hop": next_hop_ip},
                    action_name="MyIngress.change_dest_mac",
                    action_params={"dest_mac": next_hop_mac}
                )
                # Add the table entry to the switch
                s1.WriteTableEntry(arp_entry)
                print("wrote to arp")
                
                print ("Add MAC table entry", next_hop_mac, egress_port, egress_mac)
                # TODO: Add table entries to "MyIngress.dmac_forward"
                # They represent the dstMAC to egress port and MAC mapping.
                # 1. Use p4info_helper's buildTableEntry() method to build a table_entry
                # 2. Add the table_entry to the switch by calling s1's WriteTableEntry() method
                dmac_entry = p4info_helper.buildTableEntry(
                    table_name="MyIngress.dmac_forward",
                    match_fields={"hdr.ethernet.dest_addr": next_hop_mac},
                    action_name="MyIngress.forward_to_port",
                    action_params={"egress_port": egress_port, "egress_mac": egress_mac}
                )
                # Add the table entry to the switch
                s1.WriteTableEntry(dmac_entry)
                print("wrote to dmac")

                print("---- TABLE ENTRIES ----")
                print_table_entries("MyIngress.ipv4_route")
                print_table_entries("MyIngress.arp_table")
                print_table_entries("MyIngress.dmac_forward")


    
    except KeyboardInterrupt:
        print(" Shutting down.")
    except grpc.RpcError as e:
        printGrpcError(e)

    ShutdownAllSwitchConnections()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='P4Runtime Controller')
    parser.add_argument('--p4info', help='p4info proto in text format from p4c',
                        type=str, action="store", required=True)
    parser.add_argument('--bmv2-json', help='BMv2 JSON file from p4c',
                        type=str, action="store", required=True)
    parser.add_argument('--routing-info', help='Routing info file',
                        type=str, action="store", required=True)
    
    args = parser.parse_args()

    if not os.path.exists(args.p4info):
        parser.print_help()
        print("\np4info file not found: %s\nHave you run 'make'?" % args.p4info)
        parser.exit(1)
    if not os.path.exists(args.bmv2_json):
        parser.print_help()
        print("\nBMv2 JSON file not found: %s\nHave you run 'make'?" % args.bmv2_json)
        parser.exit(1)
    if not os.path.exists(args.routing_info):
        parser.print_help()
        print("\nBMv2 JSON file not found: %s\nHave you run 'make'?" % args.bmv2_json)
        parser.exit(1)
    
    main(args.p4info, args.bmv2_json, args.routing_info)
