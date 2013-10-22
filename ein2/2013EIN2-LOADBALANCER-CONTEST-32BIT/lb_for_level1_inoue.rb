# -*- coding: utf-8 -*-
require "pp"
require "counter"
class LoadBarancerForLevel1 < Controller

  #periodic_timer_event(:show_counter, 10)

  def start
    @fdb = {}   
    @counter = Counter.new
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
      # nothing to do
    end    
    @counter.add message.macsa, 1, message.total_len
  end

  def flow_removed(dpid, message)
    @counter.add message.match.dl_src, message.packet_count, message.byte_count
  end
  
  private

  def show_counter
    puts Time.now
    @counter.each_pair do | mac, counter |
      puts"#{ mac } #{counter[:packet_count]} packets (#{counter[:byte_count]} bytes)"
    end
  end

  def handle_arp_request(dpid, message, port)
    puts ""
    puts "ARP Requestを受信。"
    puts "送信元ポート番号：" +  message.in_port.to_s
    puts "送信元MACアドレス：" + message.arp_sha.to_s
    puts "送信元IPアドレス：" + message.arp_spa.to_s
    puts "宛先MACアドレス：" + message.arp_tha.to_s
    puts "宛先IPアドレス：" + message.arp_tpa.to_s
    #if port
    #  flow_mod_add dpid, message, port
    #  packet_out dpid, message, port
    #else
      packet_flood_to_super dpid, message
    #end
  end

  def handle_arp_reply(dpid, message, port)
    puts ""
    puts "ARP Replyを受信。"
    puts "送信元ポート番号：" + message.in_port.to_s
    puts "送信元MACアドレス：" + message.arp_sha.to_s
    puts "送信元IPアドレス：" + message.arp_spa.to_s
    puts "宛先MACアドレス：" + message.arp_tha.to_s
    puts "宛先IPアドレス：" + message.arp_tpa.to_s
    #if port
    #  flow_mod_add dpid, message, port
    #  packet_out dpid, message, port
    #else
      packet_flood dpid, message
    #end
  end

  def handle_ipv4(dpid, message, port)
    puts ""
    puts "IPパケットを受信。"
    puts "送信元IPアドレス：" + message.ipv4_saddr.to_s
    puts "宛先IPアドレス：" + message.ipv4_daddr.to_s
    if message.ipv4_daddr.to_s == "192.168.0.250"
      if port
        flow_mod_add dpid, message, port
        packet_out dpid, message, port
      else
        packet_flood_to_super dpid,message
      end
    else
      if port
        flow_mod_add dpid, message, port
        packet_out dpid, message, port
      else
        packet_flood dpid, message
      end
    end
  end

  def flow_mod_add(dpid, message, port)
    puts "フローテーブル書き込み。"
    puts "送信元IPアドレス：" + message.ipv4_saddr.to_s
    puts "宛先IPアドレス：" + message.ipv4_daddr.to_s
    puts "宛先ポート番号：" + port.to_s
    send_flow_mod_add(
                      dpid,
                      :hard_timeout => 10,
                      :match => ExactMatch.from( message ),
                      :actions => Trema::SendOutPort.new(port)
                      )
  end

  def flow_mod_add_to_super(dpid, message, port)
    send_flow_mod_add(
                      dpid,
                      :hard_timeout => 10,
                      :match => ExactMatch.from( message ),
                      :actions => Trema::SendOutPort.new(port)
                      )
  end

  def packet_out(dpid, message, port)
    send_packet_out(
                    dpid,
                    :packet_in => message,
                    :actions => Trema::SendOutPort.new( port )
                    )
  end

  def packet_flood(dpid, message)
    output_sent_packet(message)
    packet_out(dpid, message, OFPP_FLOOD)
  end 

  def packet_flood_to_super(dpid, message)
    action = create_action_to_super(OFPP_FLOOD)
    puts "宛先を192.168.0.255に書き換え！"
    output_sent_packet(message)
    send_packet_out(
                    dpid,
                    :packet_in => message,
                    :actions => action
                    )
  end

  def create_action_to_super(port)
    [
     Trema::SetIpDstAddr.new("192.168.0.255"),
     Trema::SendOutPort.new(port)
    ]
  end

  def create_action_from_super(port)
    [
     Trema::SetIpSrcAddr.new("192.168.0.252"),
     Trema::SendOutPort.new(port)
    ]
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
      if message.ipv4_saddr.to_s == "192.168.0.252" 
        @packet_type = "Data Packet"
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
      print( "sent ", @packet_num, " ", @packet_type, "s!\n")
    end
  end

end
