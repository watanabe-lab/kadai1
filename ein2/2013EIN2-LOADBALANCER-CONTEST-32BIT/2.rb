# -*- coding: utf-8 -*-
require "pp"
require "loadbalancer-utils"
require "counter"
class LoadBarancerForLevel1 < Controller
  include LoadBalancerUtils
  periodic_timer_event(:show_counter, 10)
  periodic_timer_event(:show_fdb_and_server, 20)

  def start
    @fdb = {}   
    # hash key is IP address(to strings), value is port number
    @server_list = {}
    # for make server list
    @initiate_arp_count = 0
    @counter = Counter.new
    # following are for debug 
    @unknown_packet = 0
    @arp_request = 0
    @arp_reply = 0
    @data_packet = 0
    @packet_type = ""
    @packet_num = 0
  end

  def switch_ready dpid
    puts dpid.to_hex
  end

  def packet_in dpid, message
    # update FDB
    @fdb[message.macsa] = message.in_port
    port = @fdb[message.macda]
    if message.arp_request?
      handle_arp_request(dpid, message, port)
    elsif message.arp_reply?
      handle_arp_reply(dpid, message, port)
    elsif message.ipv4?
      handle_ipv4(dpid, message, port)
    else
      handle_initiate_packet(dpid)
    end    
    @counter.add message.macsa, 1, message.total_len
  end

  def flow_removed(dpid, message)
    @counter.add message.match.dl_src, message.packet_count, message.byte_count
  end
  
  private


  def handle_initiate_packet(dpid)
    if @initiate_arp_count < 5
      last_ip = 250 + @initiate_arp_count
      @initiate_arp_count += 1
      tpa = "192.168.0." + last_ip.to_s
      arp_request = create_arp_request_from(Mac.new("00:00:00:00:00:00"), IPAddr.new(tpa), IPAddr.new("192.168.0.50"))
      send_packet_out(
                      dpid,
                      :data => arp_request,
                      :actions => SendOutPort.new(OFPP_FLOOD)
                      )
      puts "作成したARP Requestを送信。"
    end
  end

  def handle_arp_request(dpid, message, port)
    puts "Arp request from " +  message.arp_spa.to_s + " to " + message.arp_tpa.to_s
    packet_flood dpid, message
  end

  def handle_arp_reply(dpid, message, port)
    puts "ARP reply from " + message.arp_spa.to_s + " to " + message.arp_tpa.to_s
    if ((message.arp_spa.to_s == "192.168.0.250"\
        || message.arp_spa.to_s == "192.168.0.251"\
        || message.arp_spa.to_s == "192.168.0.252"\
        || message.arp_spa.to_s == "192.168.0.253"\
        || message.arp_spa.to_s == "192.168.0.254"\
        ) && @server_list.length < 5)
      @server_list[message.arp_spa.to_s] = message.arp_sha
    else
      packet_flood dpid, message
    end
  end

  def handle_ipv4(dpid, message, port)
    puts "ipv4 from " + message.ipv4_saddr.to_s + " to " + message.ipv4_daddr.to_s
    if port
      flow_mod_add_to_super dpid, message, port
      packet_out_to_super dpid, message, port
    else
      packet_flood dpid,message
    end
  end

  def flow_mod_add(dpid, message, port)
    if message.ipv4?
      saddr = message.ipv4_saddr.to_s
      daddr = message.ipv4_daddr.to_s
    elsif message.arp_request? || message.arp_reply?
      saddr = message.arp_spa.to_s
      daddr = message.arp_tpa.to_s
    else
      saddr = message.macsa.to_s
      daddr = message.macda.to_s
    end
    send_flow_mod_add(
                      dpid,
                      :hard_timeout => 10,
                      :match => ExactMatch.from( message ),
                      :actions => Trema::SendOutPort.new(port)
                      )
  end

  def flow_mod_add_to_super(dpid, message, port)
    if message.ipv4?
      saddr = message.ipv4_saddr
      daddr = message.ipv4_daddr
    elsif message.arp_request? || message.arp_reply?
      saddr = message.arp_spa
      daddr = message.arp_tpa
    else
      saddr = 0
      daddr = 0
    end
    if daddr.to_s == "192.168.0.250"
      new_ip = "192.168.0.252"
      new_mac = @server_list[new_ip].to_s
      port = @fdb[@server_list["192.168.0.252"]] 
puts " --> to " + new_ip
      send_flow_mod_add(
                        dpid,
                        :hard_timeout => 10,
                        :match => ExactMatch.from(message),
                        :actions => [
                                     Trema::SetIpDstAddr.new(new_ip),
                                     Trema::SetEthDstAddr.new(new_mac),
                                     Trema::SendOutPort.new(port)
                                     ]
                        )
    else
      new_ip = "192.168.0.250"
      new_mac = @server_list[new_ip].to_s
puts " --> from " + new_ip
      send_flow_mod_add(
                        dpid,
                        :hard_timeout => 10,
                        :match => ExactMatch.from(message),
                        :actions => [
                                     Trema::SetIpSrcAddr.new(new_ip),
                                     Trema::SetEthSrcAddr.new(new_mac),
                                     Trema::SendOutPort.new(port)
                                    ]
                       )
    end


 
  end

  def packet_out(dpid, message, port)
    output_sent_packet(message)
    send_packet_out(
                    dpid,
                    :packet_in => message,
                    :actions => Trema::SendOutPort.new( port )
                    )
  end

  def packet_out_to_super(dpid, message, port)
    output_sent_packet(message)
    if message.ipv4?
      saddr = message.ipv4_saddr
      daddr = message.ipv4_daddr
    elsif message.arp_request? || message.arp_reply?
      saddr = message.arp_spa
      daddr = message.arp_tpa
    else
      saddr = 0
      daddr = 0
    end
    if daddr.to_s == "192.168.0.250"
      new_ip = "192.168.0.251"
      new_mac = @server_list[new_ip].to_s
      port = @fdb[@server_list["192.168.0.251"]] 
      send_packet_out(
                      dpid,
                      :packet_in => message,
                      :actions => [
                                   Trema::SetIpDstAddr.new(new_ip),
                                   Trema::SetEthDstAddr.new(new_mac),
                                   Trema::SendOutPort.new( port ),
                                  ]
                      )
    else
      send_packet_out(
                      dpid,
                      :packet_in => message,
                      :actions => Trema::SendOutPort.new( port )
                      )
    end
  end

  def packet_flood(dpid, message)
    packet_out(dpid, message, OFPP_FLOOD)
  end 

  def output_sent_packet(message)
    if message.arp_request?
      @packet_type = "ARP Request"
      @arp_request += 1
      @packet_num = @arp_request
    elsif message.arp_reply?
      @packet_type = "ARP Reply"
      @arp_reply += 1
      @packet_num = @arp_reply
    elsif message.ipv4?
      if message.ipv4_saddr.to_s == "192.168.0.251" 
        @packet_type = "Ack for Data Packet"
        @data_packet += 1
        @packet_num = @data_packet
      else
        @packet_type = nil
      end
    else
      @packet_type = "Unknown Packet"
      @unknown_packet += 1
      @packet_num = @unknown_packet
    end
    if @packet_type
    end
  end

  def show_counter
    puts Time.now
    @counter.each_pair do | mac, counter |
      puts"#{ mac } #{counter[:packet_count]} packets (#{counter[:byte_count]} bytes)"
    end
  end

  def show_fdb_and_server
    puts "FDB(Forwaring Data Base) is:"
    @fdb.each do | macsa, port_num |
      print "ポート番号：" + port_num.to_s
      puts "   MACアドレス：" + macsa.to_s
    end
    puts ""
    puts "Server List is"
    @server_list.each do | ipaddress, macaddress |
      print "IPアドレス：" + ipaddress
      puts "   MACアドレス：" + macaddress.to_s
    end
  end
end
