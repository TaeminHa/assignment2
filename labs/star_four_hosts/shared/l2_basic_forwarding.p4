/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<48> macAddr_t;
header ethernet_t {
    /* TODO: Define ethernet header*/ 
    macAddr_t src_addr;
    macAddr_t dest_addr;
    bit<16> ether_type;
}

/* digest format for mac learning*/
struct mac_learn_digest_t {
    /* TODO */ 
    macAddr_t src_mac;
    bit<9> ingress_port;
}

struct metadata {
    /* empty */
}

struct headers {
    ethernet_t ethernet;
}

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
        packet.extract(hdr.ethernet);
        transition accept;
    }
}


/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {  }
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

    action forward_to_port(bit<9> egress_port) {
        standard_metadata.egress_spec = egress_port;
    }

    action broadcast() {
        standard_metadata.mcast_grp = (bit<16>) standard_metadata.ingress_port; 
    }
    /* learn() sends srcMAC to ingress port mapping to the controller */
    /* The controller should update the both smac_table entry and dmac_entry*/
    action learn() {
        mac_learn_digest_t mac_learn_msg;

        /* TODO: Fill the digest message with srcMAC and ingress port */
        mac_learn_msg.src_mac = hdr.ethernet.src_addr;
        mac_learn_msg.ingress_port = standard_metadata.ingress_port;
        
        /* send the digest message to the controller */
        digest<mac_learn_digest_t>(1, mac_learn_msg);
    }

    /* define forwarding table */
    table dmac_forward {
        /* TODO: define key, actions, and default action for the table */ 
        key = {
            hdr.ethernet.dest_addr : exact;
        }
        actions = {
            forward_to_port;
            broadcast; // default action on miss
        }
        default_action = broadcast();

        size = 4;
        support_timeout = true;
    }

    /* check if the mac address to port mapping exists */
    table smac_table{
        /* TODO: define key, actions, and default action for the table */  
        key = {
            hdr.ethernet.src_addr : exact;
        }
        actions = {
            learn; // apply learn if there is no entry
        }
        default_action = learn(); 

        size = 4;
        support_timeout = true;
    }

    /* applying tables */
    apply {
        smac_table.apply();
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

    }
}


/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
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
