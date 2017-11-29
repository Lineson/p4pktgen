/*
Copyright 2017 Cisco Systems, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

#include <core.p4>
#include <v1model.p4>


typedef bit<48>  EthernetAddress;

header ethernet_t {
    EthernetAddress dstAddr;
    EthernetAddress srcAddr;
    bit<16>         etherType;
}

header ipv4_t {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

struct fwd_metadata_t {
    bit<16> received_ipv4_hdr_checksum;
    bit<16> ipv4_hdr_correct_checksum;
    bit<16> checksum_state;
    bit<16> new_ipv4_checksum_from_scratch;
}

struct metadata {
    fwd_metadata_t fwd_metadata;
}

struct headers {
    ethernet_t       ethernet;
    ipv4_t           ipv4;
}


#include "ones-comp-code.p4"
//#include "ones-comp-code-issue983-workaround.p4"


parser IngressParserImpl(packet_in buffer,
                         out headers hdr,
                         inout metadata user_meta,
                         inout standard_metadata_t standard_metadata)
{
    //InternetChecksum() ck;
    bit<16> ck_sum;

    state start {
        buffer.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4;
            default: accept;
        }
    }
    state parse_ipv4 {
        buffer.extract(hdr.ipv4);

        // To make the equations smaller, and perhaps easier to debug
        // if there are problems there, pretend that the IPv4 header
        // checksum is only calculated over some of the 16-bit words
        // of the IPv4 header, not all of them.
        //bit<16> word00 = (hdr.ipv4.version ++ hdr.ipv4.ihl ++ hdr.ipv4.diffserv);
        bit<16> word01 = hdr.ipv4.totalLen;
        bit<16> word02 = hdr.ipv4.identification;
        //bit<16> word03 = (hdr.ipv4.flags ++ hdr.ipv4.fragOffset);
        //bit<16> word04 = (hdr.ipv4.ttl ++ hdr.ipv4.protocol);
        //bit<16> word05 = hdr.ipv4.hdrChecksum;
        bit<16> word06 = hdr.ipv4.srcAddr[31:16];
        bit<16> word07 = hdr.ipv4.srcAddr[15:0];
        //bit<16> word08 = hdr.ipv4.dstAddr[31:16];
        //bit<16> word09 = hdr.ipv4.dstAddr[15:0];

        bit<32> tmp1a = (
            //((bit<32>) word00) +
            ((bit<32>) word01) +
            ((bit<32>) word02) +
            //((bit<32>) word03) +
            //((bit<32>) word04) +
            //((bit<32>) word05) +
            ((bit<32>) word06) +
            ((bit<32>) word07)
            //((bit<32>) word08) +
            //((bit<32>) word09)
            );
        bit<32> tmp1b = ((bit<32>) tmp1a[15:0]) + ((bit<32>) tmp1a[31:16]);
        user_meta.fwd_metadata.ipv4_hdr_correct_checksum = ~(tmp1b[15:0] + tmp1b[31:16]);

        // See Note 1
        //ck.clear();
        ck_sum = 0;
        //ck.subtract({
        //    /* 16-bit words 0-1 */ hdr.ipv4.srcAddr,
        //    /* 16-bit words 2-3 */ hdr.ipv4.dstAddr
        //});
        bit<16> word0 = ~hdr.ipv4.srcAddr[31:16];
        bit<16> word1 = ~hdr.ipv4.srcAddr[15:0];
        //bit<16> word2 = ~hdr.ipv4.dstAddr[31:16];
        //bit<16> word3 = ~hdr.ipv4.dstAddr[15:0];
        bit<16> word4 = ~hdr.ipv4.hdrChecksum;

        // remove them from ck_sum by adding ~ of each using one's
        // complement sum
        bit<32> tmp2a = (
            ((bit<32>) ck_sum) +
            ((bit<32>) word0) +
            ((bit<32>) word1) +
            //((bit<32>) word2) +
            //((bit<32>) word3) +
            ((bit<32>) word4));
        bit<32> tmp2b = ((bit<32>) tmp2a[15:0]) + ((bit<32>) tmp2a[31:16]);
        ck_sum = tmp2b[15:0] + tmp2b[31:16];
        user_meta.fwd_metadata.checksum_state = ck_sum;

        transition accept;
    }
}


control ingress(inout headers hdr,
                inout metadata user_meta,
                inout standard_metadata_t standard_metadata) {
    action forward_v4(bit<9> port, bit<32> srcAddr, bit<32> dstAddr) {
        hdr.ipv4.srcAddr = srcAddr;
        hdr.ipv4.dstAddr = dstAddr;
        //send_to_port(ostd, port);      
        standard_metadata.egress_spec = port;
    }
    table nat_v4 {
        key = {
            hdr.ipv4.srcAddr : exact;
            hdr.ipv4.dstAddr : exact;
        }
        actions = {
            forward_v4;
        }
        default_action = forward_v4(0, 1, 1);
    }
    table debug_table_0 {
        key = {
            user_meta.fwd_metadata.received_ipv4_hdr_checksum : exact;
            user_meta.fwd_metadata.ipv4_hdr_correct_checksum : exact;
            user_meta.fwd_metadata.checksum_state : exact;
            hdr.ipv4.srcAddr : exact;
            hdr.ipv4.dstAddr : exact;
            hdr.ipv4.hdrChecksum : exact;
            user_meta.fwd_metadata.new_ipv4_checksum_from_scratch : exact;
            hdr.ethernet.dstAddr : exact;
        }
        actions = {
            NoAction;
        }
    }
    table debug_table_1 {
        key = {
            user_meta.fwd_metadata.received_ipv4_hdr_checksum : exact;
            user_meta.fwd_metadata.ipv4_hdr_correct_checksum : exact;
            user_meta.fwd_metadata.checksum_state : exact;
            hdr.ipv4.srcAddr : exact;
            hdr.ipv4.dstAddr : exact;
            hdr.ipv4.hdrChecksum : exact;
            user_meta.fwd_metadata.new_ipv4_checksum_from_scratch : exact;
            hdr.ethernet.dstAddr : exact;
        }
        actions = {
            NoAction;
        }
    }
    table debug_table_2 {
        key = {
            user_meta.fwd_metadata.received_ipv4_hdr_checksum : exact;
            user_meta.fwd_metadata.ipv4_hdr_correct_checksum : exact;
            user_meta.fwd_metadata.checksum_state : exact;
            hdr.ipv4.srcAddr : exact;
            hdr.ipv4.dstAddr : exact;
            hdr.ipv4.hdrChecksum : exact;
            user_meta.fwd_metadata.new_ipv4_checksum_from_scratch : exact;
            hdr.ethernet.dstAddr : exact;
        }
        actions = {
            NoAction;
        }
    }
    //InternetChecksum() ck;
    bit<16> ck_sum;
    apply {
        user_meta.fwd_metadata.received_ipv4_hdr_checksum = hdr.ipv4.hdrChecksum;
        user_meta.fwd_metadata.new_ipv4_checksum_from_scratch = 0;
        debug_table_0.apply();
        if (hdr.ipv4.isValid()) {
            if (! (hdr.ipv4.version == 4 &&
                    hdr.ipv4.ihl == 5 &&
                    hdr.ipv4.totalLen == 20 &&
//                    ((hdr.ipv4.protocol == 6 && hdr.ipv4.totalLen == 20+20) ||
//                        (hdr.ipv4.protocol == 17 && hdr.ipv4.totalLen == 20+8)) &&
                    hdr.ipv4.flags == 0 &&
                    hdr.ipv4.fragOffset == 0 &&
                    hdr.ipv4.ttl >= 2 &&
                    hdr.ipv4.hdrChecksum == user_meta.fwd_metadata.ipv4_hdr_correct_checksum &&
                    hdr.ipv4.srcAddr[15:0] != 0 &&
                    hdr.ipv4.dstAddr != 0))
            {
                exit;
            }
            nat_v4.apply();
        }

        // Do an incremental calculation of the outgoing IPv4 header
        // checksum.

        // restore state of removing original src and dst IPv4
        // addresses, and original hdr checksum.
        ck_sum = user_meta.fwd_metadata.checksum_state;
        // Add in effect of new src and dst IPv4 addresses.
        ones_comp_sum_b48.apply(ck_sum,
            //ck_sum ++ hdr.ipv4.srcAddr ++ hdr.ipv4.dstAddr);
            ck_sum ++ hdr.ipv4.srcAddr);
        hdr.ipv4.hdrChecksum = ~ck_sum;
        

        // Calculate IPv4 header checksum from scratch.
        //ck.clear();
        ck_sum = 0;
/*
        ck.add({
            hdr.ipv4.version, hdr.ipv4.ihl, hdr.ipv4.diffserv,
            hdr.ipv4.totalLen,
            hdr.ipv4.identification,
            hdr.ipv4.flags, hdr.ipv4.fragOffset,
            hdr.ipv4.ttl, hdr.ipv4.protocol,
            //hdr.ipv4.hdrChecksum, // intentionally leave this out
            hdr.ipv4.srcAddr,
            hdr.ipv4.dstAddr });
*/
        ones_comp_sum_b80.apply(ck_sum,
            ck_sum ++
            //hdr.ipv4.version ++ hdr.ipv4.ihl ++ hdr.ipv4.diffserv ++
            hdr.ipv4.totalLen ++
            hdr.ipv4.identification ++
            //hdr.ipv4.flags ++ hdr.ipv4.fragOffset ++
            //hdr.ipv4.ttl ++ hdr.ipv4.protocol ++
            //hdr.ipv4.hdrChecksum ++ // intentionally leave this out
            hdr.ipv4.srcAddr
            //hdr.ipv4.dstAddr
            );
        //hdr.ipv4.hdrChecksum = ck.get();
        user_meta.fwd_metadata.new_ipv4_checksum_from_scratch = ~ck_sum;

        debug_table_1.apply();
        if (hdr.ipv4.hdrChecksum != user_meta.fwd_metadata.new_ipv4_checksum_from_scratch) {
            hdr.ethernet.dstAddr = 0xbad1bad1bad1;
        } else {
            if (hdr.ipv4.hdrChecksum == 0xffff) {
                // This should be impossible
                hdr.ethernet.dstAddr = 0xbad2bad2bad2;
            } else if (hdr.ipv4.hdrChecksum == 0x0000) {
                // This should be possible
                hdr.ethernet.dstAddr = 0xc000c000c000;
            } else {
                // This is the common case
                hdr.ethernet.dstAddr = 0xc001c001c001;
            }
        }
        debug_table_2.apply();
    }
}

control egress(inout headers hdr,
               inout metadata user_meta,
               inout standard_metadata_t standard_metadata)
{
    apply { }
}

control DeparserImpl(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
    }
}

control verifyChecksum(inout headers hdr, inout metadata meta) {
    apply { }
}

control computeChecksum(inout headers hdr, inout metadata meta) {
    apply { }
}

V1Switch(IngressParserImpl(),
         verifyChecksum(),
         ingress(),
         egress(),
         computeChecksum(),
         DeparserImpl()) main;
