# -*- coding: utf-8 -*-
require "pp"
require "loadbalancer-utils"
require "counter"
class LoadBarancerForLevel1 < Controller
  include LoadBalancerUtils
  periodic_timer_event(:show_fdb_and_server, 20)

  def start
    # fdb_mac(key, value) = (macaddr(string), port(int))
    # fdb_ip(key, value) = (ipaddr(string), macaddr(string))
    @fdb_mac = {}   
    @fdb_ip = {}
    @server_list = []
    @made_server_list = 0 
    @fine_server = "192.168.0.252"
    @init_connect_server = "192.168.0.250"
    @my_ipaddr = "192.168.0.50"
    # 変数初期化  by河野
    initializeServers
  end

  def switch_ready dpid
    puts "switch ready " + dpid.to_hex
  end

  def packet_in dpid, message
    # update FDB
    @fdb_mac[message.macsa.to_s] = message.in_port.to_i
    if message.arp_request?
      handle_arp_request(dpid, message)
    elsif message.arp_reply?
      handle_arp_reply(dpid, message)
    elsif message.ipv4?
      handle_ipv4(dpid, message)
    else
      handle_initiate_packet(dpid)
    end    
  end

  def flow_removed dpid, message
    puts "flow removed!"
  end
  
  private

  def handle_initiate_packet dpid
      if @made_server_list == 0
        send_arp_request_to_make_server_list(dpid)
      end
  end

  def handle_arp_request dpid, message
    source_ip = message.arp_spa.to_s
    target_ip = message.arp_tpa.to_s
    puts "ARP Request from " + source_ip + " to " + target_ip
    @fdb_ip[source_ip] = message.macsa.to_s
    packet_out(dpid, message, SendOutPort.new(OFPP_FLOOD))
  end

  def send_arp_request_to_make_server_list dpid
    for ip_count in 128..254
      tpa = "192.168.0." + ip_count.to_s
      arp_request = create_arp_request_from(
        Mac.new("00:00:00:00:00:00"),
        IPAddr.new(tpa),
        IPAddr.new(@my_ipaddr))
      make_arp_request_packet(dpid, arp_request, SendOutPort.new(OFPP_FLOOD))
    end
    @made_server_list = 1 
  end

  def handle_arp_reply dpid, message
    source_ip = message.arp_spa.to_s
    target_ip = message.arp_tpa.to_s
    puts "ARP Reply from " + source_ip + " to " + target_ip
    @fdb_ip[source_ip] = message.macsa.to_s
    if target_ip == @my_ipaddr
      update_server_list(message)
    else
      #port = @fdb_mac[@fdb_ip[target_ip]]
      #packet_out(dpid, message, SendOutPort.new(port))
      packet_out(dpid, message, SendOutPort.new(OFPP_FLOOD))
    end
  end

  def update_server_list message
    source_ip = message.arp_spa.to_s
    @server_list.push(source_ip)
  end

  def handle_ipv4 dpid, message
    source_ip = message.ipv4_saddr.to_s
    dest_ip = message.ipv4_daddr.to_s
    puts "IPv4 from " + source_ip + " to " + dest_ip
    port = @fdb_mac[message.macda.to_s]
    if port
      # 送信先サーバ番号を更新  by河野
      selectNextServer
      send_packet_and_update_flow(dpid, message)
    else
      packet_out(dpid, message, SendOutPort.new(OFPP_FLOOD))
    end
  end

  def flow_mod dpid, message, action
    send_flow_mod_add(
      dpid,
      :hard_timeout => 10,
      :match => ExactMatch.from(message),
      :actions => action
    )
  end

  def send_packet_and_update_flow dpid, message
    daddr = message.ipv4_daddr.to_s
    action = 0
    if @server_list.include?(daddr) 
      # 送信先選択  by河野
      dst_ip = "192.168.0.25" + @next_superserver.to_s
      # dst_ip = @fine_server 
      dst_mac = @fdb_ip[dst_ip]
      port = @fdb_mac[dst_mac]
      action = create_action_from_dst(dst_ip, dst_mac, port)
      puts " --> to " + dst_ip
    else
      # ACK
      # ACK確認  by河野
      checkAck(message.ipv4_saddr.to_s[-1,1].to_i)
      src_ip = @init_connect_server
      src_mac = @fdb_ip[src_ip]
      port = @fdb_mac[message.macda.to_s] 
      action = create_action_from_src(src_ip, src_mac, port)
      puts " --> from " + src_ip
    end
    flow_mod(dpid, message, action)
    packet_out(dpid, message, action)
  end

  def create_action_from_dst new_ip, new_mac, port
    [
      Trema::SetIpDstAddr.new(new_ip),
      Trema::SetEthDstAddr.new(new_mac),
      Trema::SendOutPort.new(port)
    ]
  end

  def create_action_from_src new_ip, new_mac, port
    [
      Trema::SetIpSrcAddr.new(new_ip),
      Trema::SetEthSrcAddr.new(new_mac),
      Trema::SendOutPort.new(port)
    ]
  end

  def make_arp_request_packet dpid, arp_data, action 
    send_packet_out(
      dpid,
      :data => arp_data,
      :actions => action 
    )
  end

  def packet_out dpid, message, action
    send_packet_out(
      dpid,
      :packet_in => message,
      :actions => action
    )
  end 

  def show_fdb_and_server
    puts ""
    puts "FDB(Forwaring Data Base) is"
    puts " IPaddr,\t\t,port\t,MACaddr"
    @fdb_ip.each do | ip, mac |
      puts " " + ip.to_s + "\t" + @fdb_mac[mac].to_s + "\t" + mac.to_s
    end
    puts ""
    puts "Server List is"
    puts " " + @server_list.join("\n ") 
  end
  
  
  
  # 変数初期化  by河野
  def initializeServers
    @server_totalNumber = 5  # サーバの総数。要設定
    @window_size = 1         # [要調整]ACKを待たずに送っていいパケット数。全て落ちたら他のサーバに切り替える
    @dual_deal_servers = 2   # [要調整]ACK待ち状態のサーバが同時にこの値になったらダウンしていると見なす
    @next_superserver = 0    # 次の送り先となるサーバID。IPアドレスの末尾
    @target_defserver = 0    # デフォルトの送り先となるサーバID
    @server_waiting_packet = Array.new(@server_totalNumber, 0)  # ACK待ちパケット数を記録
  end
  
  # 送信先を選ぶ処理  by河野
  # 返り値 : 送信先サーバのID。IPアドレスの末尾
  def selectNextServer
    i = @target_defserver
    while @server_waiting_packet[i] >= @window_size
      # 数値はACK待ちパケット数。要調整
      i = (i + 1) % @server_totalNumber
    end
    @next_superserver = i
    @server_waiting_packet[i] += 1
    # 復活判定
    if (i - @target_defserver + @server_totalNumber) % @server_totalNumber >= @dual_deal_servers
      # 数値は連なったACK待ちサーバの数。要調整
      @server_waiting_packet[@target_defserver] = 0
      @target_defserver = (@target_defserver + 1) % @server_totalNumber
    end
  end
  
  
  # サーバからACKを受け取った時の処理  by河野
  # 引数 : ACKを送信したサーバのID。IPアドレスの末尾
  def checkAck(server_id)
    @server_waiting_packet[server_id] -= 1   # 受信待ちACK数を1つ減らす
  end

  
end
