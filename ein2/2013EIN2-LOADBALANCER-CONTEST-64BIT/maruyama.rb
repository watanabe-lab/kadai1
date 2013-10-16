# 複数のスイッチはつながっていないとする
class Packet < Controller

  def start
    @fdb_port = {} 
    @fdb_swit = {}
  end
  
  def switch_ready dpid  
    puts "start switch " + dpid.to_hex
  end

  def packet_in dpid, message 
    puts "(switch, port): (" + dpid.to_hex + ", " + message.in_port.to_s + ")"
    source_addr = message.macsa 
    dest_addr = message.macda 
    @fdb_port[source_addr] = message.in_port
    @fdb_swit[source_addr] = dpid
    # Forwarding DBの参照
    out_port = @fdb_port[dest_addr] 
    out_swit = @fdb_swit[dest_addr]
    if !out_swit || out_swit == dpid
      if out_port
        flow_add(dpid, message, out_port)
      else
        out_port = OFPP_FLOOD
        out_swit = dpid
      end
      send_packet(out_swit, message, out_port)
    else
      # 何もしない
    end
  end

  private

  def flow_add dpid, message, out_port
    out_port = @fdb_port[message.macda] 
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
end
