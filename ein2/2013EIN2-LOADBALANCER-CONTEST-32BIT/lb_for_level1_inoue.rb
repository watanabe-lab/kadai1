# -*- coding: utf-8 -*-
require "pp"
class LoadBarancerForLevel1 < Controller

  #add_periodic_timer_event(:display_switch_list, 5)

  def start
    @fdb = {}   
  end

#  def switch_ready dpid
#    puts dpid.to_hex
#  end

  def packet_in dpid, message
    @fdb[message.macsa] = message.in_port
    port = @fdb[message.macda] 
#    if port
#      flow_mod_add dpid, message, port
#      packet_out dpid, message, port
#    else
      packet_flood dpid, message
#    end
  end

  
  private


  def flow_mod_add(dpid, message, port)
    send_flow_mod_add(
                      dpid,
                      :match => ExactMatch.from( message ),
                      :actions => Trema::SendOutPort.new( port )
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
    send_packet_out(
                    dpid,
                    :packet_in => message,
                    :actions => Trema::SendOutPort.new( OFPP_FLOOD )
                    )
  end
end
