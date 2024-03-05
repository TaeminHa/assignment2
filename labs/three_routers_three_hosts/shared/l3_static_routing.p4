/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<48> macAddr_t;
typedef bit<32> ipAddr_t;
header ethernet_t {
    /* TODO: define Ethernet header */ 
    macAddr_t src_addr;
    macAddr_t dest_addr;
    bit<16> ether_type;
}

/* a basic ip header without options and pad */
header ipv4_t {
    bit<4> version;           // IP version
    bit<4> ihl;               // Internet Header Length (IHL)
    bit<8> diffserv;          // Differentiated Services (DSCP/ECN)
    bit<16> total_len;        // Total Length
    bit<16> identification;   // Identification
    bit<3> flags;             // Flags
    bit<13> frag_offset;      // Fragment Offset
    bit<8> ttl;               // Time to Live (TTL)
    bit<8> protocol;          // Protocol
    bit<16> hdr_checksum;     // Header Checksum
    ipAddr_t src_addr;        // Source IP address
    ipAddr_t dest_addr;       // Destination IP address

}

struct metadata {
    ipAddr_t next_hop;
}

struct headers {
    ethernet_t ethernet;
    ipv4_t ipv4;
}

/*************************************************************************
*********************** M A C R O S  ***********************************
*************************************************************************/
#define ETHER_IPV4 0x0800

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
        transition parse_ethernet;
    }
    state parse_ethernet {
        /* TODO: do ethernet header parsing */
        /* if the frame type is IPv4, go to IPv4 parsing */ 
        // If the EtherType is IPv4 (0x0800), go to IPv4 parsing
        ETHER_IPV4 : parse_ipv4;
        // Add other EtherType values and transitions as needed
        default : accept; // Default to accepting the packet
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }
}


/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {
        /* TODO: verify checksum using verify_checksum() extern */
        /* Use HashAlgorithm.csum16 as a hash algorithm */ 
        verify_checksum(HashAlgorithm.csum16, hdr);
    }
}


/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {

    /* define actions */
    action drop() {
        mark_to_drop(standard_metadata);
    }

    action forward_to_port(bit<9> egress_port, macAddr_t egress_mac) {
        /* TODO: change the packet's source MAC address to egress_mac */
        hdr.ethernet.src_addr = egress_mac;
        /* Then set the egress_spec in the packet's standard_metadata to egress_port */
        standard_metadata.egress_spec = egress_port
    }
   
    action decrement_ttl() {
        /* TODO: decrement the IPv4 header's TTL field by one */
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    action forward_to_next_hop(ipAddr_t next_hop){
        /* TODO: write next_hop to metadata's next_hop field */
        meta.next_hop = next_hop;
    }

    action change_dst_mac (macAddr_t dst_mac) {
        /* TODO: change a packet's destination MAC address to dst_mac*/
        hdr.ethernet.dest_addr = dst_mac;
    }

    /* define routing table */
    table ipv4_route {
        key = {
            hdr.ipv4.dest_addr: lpm
        }
        actions = {
            forward_to_next_hop;
            drop; // Default action if no match
        }
        // TODO: Not sure about this
        size = 3;
        /* TODO: define a static ipv4 routing table */
        /* Perform longest prefix matching on dstIP then */
        /* record the next hop IP address in the metadata's next_hop field*/
    }

    /* define static ARP table */
    table arp_table {
        key = {
            meta.next_hop: exact; // Exact match on next hop IP address
        }
        actions = {
            change_dst_mac;
            forward_to_port;
            drop; // Default action if no match
        }
        size = 3;

        /* TODO: define a static ARP table */
        /* Perform exact matching on metadata's next_hop field then */
        /* modify the packet's src and dst MAC addresses upon match */
    }


    /* define forwarding table */
    table dmac_forward {
        key = {
            hdr.ethernet.dst_addr: exact; // Exact match on destination MAC address
        }
        actions = {
            forward_to_port;
            drop; // Default action if no match
        }
        size = 3;

        /* TODO: define a static forwarding table */
        /* Perform exact matching on dstMAC then */
        /* forward to the corresponding egress port */ 
    }
   
    /* applying dmac */
    apply {
        /* TODO: Implement a routing logic */
        /* 1. Lookup IPv4 routing table */
        /* 2. Upon hit, lookup ARP table */
        /* 3. Upon hit, Decrement ttl */
        /* 4. Then lookup forwarding table */  

        ipv4_route.apply();
        if (ipv4_route.hit) {
            arp_table.apply();
            if (arp_table.hit)
                decrement_ttl();
        }
        dmac_forward.apply();

    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {


    apply {  }
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers hdr, inout metadata meta) {
    apply {
        /* TODO: calculate the modified packet's checksum */
        /* using update_checksum() extern */
        /* Use HashAlgorithm.csum16 as a hash algorithm */
        update_checksum(HashAlgorithm.csum16, hdr);
    } 
}


/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

//switch architecture
V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;