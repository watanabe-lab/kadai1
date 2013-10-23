#!/usr/bin/env ruby
#
#
require 'rubygems'
require 'json'
require 'pp'
require 'open3'

TREMA = "trema"
WTIME = 5
CLIENT = "./bin/client"
SERVER = "./bin/server"
DIR_HP_FILE = "/tmp/"
HP_FILE_PREFIX = "server"
PID_PATH = "/tmp/"#"/var/run/"
PID_DIR = "OpenFlow-LB"
PID_FILE_PREFIX_CLIENT = "client."
PID_FILE_PREFIX_SERVER = "server."
PID_DIR_PATH = PID_PATH + PID_DIR + "/"


$pids_s = []
$pids_c = []
$pids_o = []

## will be called, when Ctrl-c is sent
Signal.trap(:INT){
	STDERR.puts
	STDERR.puts "invoke SIGINT"
	kill_all_processes
	exit 0
}

## kill all processes including servers, clients and trema
## PIDs for server and clients are in PID files
def kill_all_processes
  puts "KILL   : all processes"
  pid_servers = PID_DIR_PATH + "/" + PID_FILE_PREFIX_SERVER + "*"
  pid_clients = PID_DIR_PATH + "/" + PID_FILE_PREFIX_CLIENT + "*"
  # for servers
  Dir::glob(pid_servers).each do |f|
    if File::ftype(f) == "file"
      pid_server = f.split( "." )[1]
      $pids_s.delete(pid_server)
      begin
        File.delete(f)
        Process.kill('KILL', pid_server.to_i)
#        puts "KILL   : server [" + pid_server + "] was killed"
      rescue Errno::ESRCH
        STDERR.puts "KILL   : server [" + pid_server + "]: No such process"
      rescue
        STDERR.puts "ERROR  : Can't kill server process [" + pid_server + "]"
      end
    end
  end
  # for clients
  Dir::glob(pid_clients).each do |f|
    if File::ftype(f) == "file"
      pid_client = f.split( "." )[1]
      $pids_c.delete(pid_client)
      begin
        File.delete(f)
        Process.kill('KILL', pid_client.to_i)
#        puts "KILL   : client [" + pid_client + "] was killed"
      rescue Errno::ESRCH
        STDERR.puts "KILL   : client [" + pid_client + "]: No such process"
      rescue
        STDERR.puts "ERROR  : Can't kill client process [" + pid_client + "]"
      end
    end
  end

  # for trema
  cmd = TREMA + " killall"
  system(cmd)

  $pids_c.each{|pid|
    if process_working?(pid.to_i) then Process.kill('KILL', pid.to_i) end
  }
  $pids_s.each{|pid|
    if process_working?(pid.to_i) then Process.kill('KILL', pid.to_i) end
  }

end

def process_working? (pid)
  begin 
    gid=Process.getpgid(pid)
    return true
  rescue
    return false
  end
end

## check number of arguments, and print usage if wrong
if(ARGV.size != 3)
  $stderr.puts "Usage: #{File.basename($0)} config_file_level trema_controler_rb trema_network_config"
  exit 0
end

puts "Starting..."
puts

## print configurations
puts "------------ Configuration ------------"
puts " + trema"
puts " |-> path     : " + TREMA
puts " |-> controler: " + ARGV[1]
puts " `-> network  : " + ARGV[2]
puts " + sever-client"
puts " `-> config   : " + ARGV[0]
puts " + PID"
puts " |-> server   : " + PID_PATH + PID_DIR + "/" + PID_FILE_PREFIX_SERVER + "*"
puts " `-> client   : " + PID_PATH + PID_DIR + "/" + PID_FILE_PREFIX_CLIENT + "*"
puts "---------------------------------------"
puts

## Kill remaining processes including servers, clients and trema by calling the method
## create directory for PID files, if not exists
if File.exists?(PID_DIR_PATH)
  kill_all_processes
else
  begin
    Dir.mkdir(PID_DIR_PATH)
    puts "MKDIR  : " + PID_DIR_PATH
  rescue
    STDERR.puts "MKDIR  : " + PID_DIR_PATH + ": Can't create directory"
    exit 1
  end
end
puts

## Delete HP files, and clean
hp_files = DIR_HP_FILE + HP_FILE_PREFIX + "_*"
begin
  Dir::glob(hp_files).each do |f|
    if File::ftype(f) == "file"
      puts "DELETE : " + f
      File.delete(f)
    end
  end
rescue
  STDERR.puts "DELETE : " + hp_files +": Can't delete files"
end
puts

## Start trema as daemon
## to kill easily by invoking "trema killall"
cmd = TREMA + " run " + ARGV[1] + " -c " + ARGV[2] + " -d"
Thread.new  {
  pid = fork {
    begin
      exec(cmd)
    rescue
      $pids_o.delete(pid)
      kill_all_processes
      exit 0
    end
  }
  $pids_o << pid
}

puts "EXECUTE: " + cmd

#rescue
#  STDERR.puts "EXECUTE: " + cmd
#  STDERR.puts "  ERROR: pathes of trema or configuration files might be wrong."
#  exit 1
#end
puts

sleep(WTIME)

## parse config file
fn = ARGV[0]
str = ""
open(fn, "r"){|f|
  f.each{|line| str = str + line} 
}
conf = JSON.parse(str)

pipes = []
results = []

## run servers
ctrlc_enable = true
puts "START  : servers"
puts
conf["server"].each{|server|
  pin_in, pin_out = IO.pipe
  pout_in, pout_out = IO.pipe
  pipes << {"in" => pin_in, "out" => pout_out}
  Thread.new {
    pid = fork {
      begin
        pin_in.close
        pout_out.close
        STDIN.reopen(pout_in)
        STDOUT.reopen(pin_out)
        if server["ip"] == "127.0.0.1"
          cmd = "#{SERVER} #{server["ip"]} #{server["port"]} #{server["max_life"]} #{server["dec_life"]} #{server["sleep_time"]}"
        else
          cmd = "ip netns exec #{server["netns"]} #{SERVER} #{server["ip"]} #{server["port"]} #{server["max_life"]} #{server["dec_life"]} #{server["sleep_time"]}"
        end
        exec(cmd)
      rescue
	$pids_s.delete(pid)
        kill_all_processes
        exit 0
      end
    }
    # write PID to PID file
    if pid != nil
      pid_file_name = PID_DIR_PATH + PID_FILE_PREFIX_SERVER + pid.to_s
      f_pid = open(pid_file_name, "w")
      f_pid.close
    end
    #
    $pids_s << pid
    #
    pout_in.close
    pin_out.close
  }
  sleep(1)
}

sleep(3) # wait to complete starting of server

# run clients
puts "START  : clients"
puts
conf["client"].each{|client|
  Thread.new {
    pid = fork {
      begin
        if client["ip"] == "127.0.0.1"
          cmd = "#{client["netns"]} #{CLIENT} #{client["ip"]} #{fn}"
        else
          cmd = "ip netns exec #{client["netns"]} #{CLIENT} #{client["ip"]} #{fn}"
        end
        exec(cmd)
        #exit! 0
      rescue
	$pids_c.delete(pid)
        kill_all_processes
        exit 0
     end
    }
    # write PID to PID file
    if pid != nil
      pid_file_name = PID_DIR_PATH + PID_FILE_PREFIX_CLIENT + pid.to_s
      f_pid = open(pid_file_name, "w")
      f_pid.close
    end
    #
    $pids_c << pid
  }
}

## wait for clients to exit, and delete PID files for clients
while !$pids_c.empty?
  pid = Process.wait
  $pids_c.delete(pid)
  # delete PID file
  pid_file_tmp = PID_DIR_PATH + PID_FILE_PREFIX_CLIENT + pid.to_s
  if File.exists?(pid_file_tmp)
    begin
      File.delete(pid_file_tmp)
    rescue
      STDERR.puts "DELETE : " + pid_file_tmp +": Can't delete files"
    end
  end
end

sleep(2) # wait to what?

## stop all servers and calculate score
puts "---------- Score ----------"
score = 0
regexp = /Score: (-*[0-9]+\.[0-9]+|[0-9]+)/
pipes.each{|pipe|
  pipe["out"].write("fin\nfin\nfin\n");
  pipe["out"].close
  while result = pipe["in"].gets("\n")
    puts " " + result
    if result =~ regexp
      score = score + $1.to_f
    end
  end
}

## wait for servers to exit, and delete PID files for servers
while !$pids_s.empty?
  pid = Process.wait
  $pids_s.delete(pid)
  # delete PID file
  pid_file_tmp = PID_PATH + PID_DIR + "/" + PID_FILE_PREFIX_SERVER + pid.to_s
  if File.exists?(pid_file_tmp)
    begin
      File.delete(pid_file_tmp)
    rescue
      STDERR.puts "DELETE : " + pid_file_tmp +": Can't delete files"
    end
  end
end

## print total score
puts "---------------------------"
puts " Total: %f" % [score]
puts "---------------------------"
puts

## kill trema
cmd = TREMA + " killall"
system(cmd)

Process.waitall

