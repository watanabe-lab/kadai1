require "pp"
require "interface"
require "router-utils2"
class Packet < Controller
  include RouterUtils

  def start
    @fdb_port = {} 
    @interfaces = Interface.new($interface)
    super_server = "192.168.0.252"
    puts "maruyama.rb start!"
  end
  
  def switch_ready dpid  
    puts "start switch " + dpid.to_hex
  end

  def packet_in dpid, message 
    if message.arp_request?
      handle_arp_request dpid, message
    elsif message.arp_reply?
      handle_arp_reply dpid, message
    elsif message.ipv4?
      handle_ipv4 dpid, message
    else
      # 何もしない
    end
  end 
      
    out_port = @fdb_port[message.macda] 
    @fdb_port[message.macsa] = in_port
    if out_port
      flow_add(dpid, message, out_port)
      send_packet(dpid, message, out_port)
    else
      flood_packet(dpid, message)
    end
  end

  private

  def handle_arp_request dpid, message
    in_port = message.in_port
    target_ipaddr = message.arp_tpa
    puts "arp request!"
    puts "target mac address(mac) " + message.arp_tha.to_s
    puts "target protocol address(ipv4) " + target_ipaddr.to_s
    hwaddr = Mac.new

    arp_request = create_arp_request2(hwaddr, addr, ipaddr)
    packet_out(dpid, arp_request, SendOutPort.new(OFPP_FLOOD))
  end

  def handle_arp_reply dpid, message
    puts "arp reply!"
    print_packet(in_port, out_port)
  end

  def handle_ipv4 dpid, message
    puts "ipv4.dest_address: " + message.ipv4_daddr.to_s
    print_packet(in_port, out_port)
  end

  def flow_add dpid, message, out_port
    send_flow_mod_add(
      dpid,
      :match => Match.from(message, :in_port, :nw_src, :nw_dst),
      :actions => SendOutPort.new(out_port))
  end

  def send_packet dpid, message, out_port
    send_packet_out(
      dpid,
      :packet_in => message,
      :actions => Trema::SendOutPort.new(out_port))
  end

  def flood_packet dpid, message
    send_packet_out(
      dpid,
      :packet_in => message,
      :actions => Trema::SendOutPort.new(OFPP_FLOOD))
  end

  def print_packet in_port, out_port
    if out_port
      puts "(" + in_port.to_s + ", " + out_port.to_s + ")"
    else
      puts "(" + in_port.to_s + ", unknown port)"
    end
  end
end
