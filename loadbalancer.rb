require "pp"
class MultipleSwitch < Controller
	def start
		@fdb = {} 
	end

	def packet_in dpid, message
		pp message
		@fdb[message.macsa] = message.in_port
		port = @fdb[message.macda]
	
		if port
			send_flow_mod_add(
				dpid,
				:match => ExactMatch.from(message),
				:actions => SendOutPort.new(port)
			)
		else
			port = OFPP_FLOOD
		end

		send_packet_out(
			dpid,
			:packet_in => message,
			:actions => Trema::SendOutPort.new(port) 
		)
	end
end
