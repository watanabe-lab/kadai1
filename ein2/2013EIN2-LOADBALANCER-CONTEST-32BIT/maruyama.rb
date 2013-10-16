class Packet < Controller

  def start
    @fdb_port = {} 
  end
  
  def switch_ready dpid  
    puts "start switch " + dpid.to_hex
  end

  def packet_in dpid, message 
    in_port = message.in_port
    out_port = @fdb_port[message.macda] 
    print_packet(in_port, out_port)
    @fdb_port[message.macsa] = in_port
    if out_port
      flow_add(out_port, message)
      send_packet(dpid, message)
    else
      flood_packet(dpid, message)
    end
  end

  private

  def flow_add dpid, message
    send_flow_mod_add(
      dpid,
      :match => Match.from(message, :in_port, :nw_src, :nw_dst),
      :actions => SendOutPort.new(dpid))
  end

  def send_packet dpid, message
    send_packet_out(
      dpid,
      :packet_in => message,
      :actions => Trema::SendOutPort.new(dpid))
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
