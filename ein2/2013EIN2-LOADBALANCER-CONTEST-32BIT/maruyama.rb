require "pp"
class Packet < Controller

  def start
    @fdb_port = {} 
    puts "maruyama.rb start!"
  end
  
  def switch_ready dpid  
    puts "start switch " + dpid.to_hex
  end

  def packet_in dpid, message 
    in_port = message.in_port
    out_port = @fdb_port[message.macda] 
if message.arp_request?
  puts "arp request!"
  puts message.arp_tha.to_s
  puts message.arp_tpa.to_s
end
if message.arp_reply?
  puts "arp reply!"
end
if message.ipv4?
  puts "ipv4.dest_address: " + message.ipv4_daddr.to_s
end
    print_packet(in_port, out_port)
    @fdb_port[message.macsa] = in_port
    if out_port
puts " OK : (" + message.macda.to_s + ", " + out_port.to_s + ")"
      flow_add(dpid, message, out_port)
      send_packet(dpid, message, out_port)
    else
      flood_packet(dpid, message)
    end
  end

  private

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
