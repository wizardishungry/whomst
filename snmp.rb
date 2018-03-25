require 'pry'
require 'ipaddr'

class Snmp
  def initialize(host)
    @host = host
  end
  def get
    data = {}
    `snmpwalk -v 2c -c public -Os #{@host} iso.3.6.1.4.1.63.501.3.3.2.1`.lines.map(&:chomp).each do |line|
      # enterprises.63.501.3.3.2.1.1.17.48.48.58.53.54.58.67.68.58.65.54.58.53.57.58.52.65 = STRING: "00:56:CD:A6:59:4A"
      parts = line.split ' = '
      key = parts[0].match /\.\d*\.\d*$/
      word = parts[1].match /^([^ ]*):/
      next unless word and word[1]
      word = word[1]
      value = (parts[1].match /: \"?([^"]*)\"?$/)[1]
      dict = data.fetch key.to_s, {}
      dict[word.to_s] = value.to_s
      data[key.to_s] = dict
    end
    grouped = {}
    data.values.map do |d|
      d['vendor'] = mac_lookup d['STRING']
      key = host_lookup(d['STRING']) || host_lookup(d["IpAddress"]) || d["IpAddress"]
      parts = key.split ' #',2
      key = parts[0]
      comment = parts[1] || ''
      d['comment'] = comment
      hosts = grouped.fetch key, []
      hosts.push d
      grouped[key] = hosts
    end
    grouped = grouped.sort_by do |key,nodes|
      (nodes.map { |node| (IPAddr.new node["IpAddress"]).to_i }).sort.first
    end
    grouped.each do |key,nodes|
      node = nodes.first
      node["zeroconf"] = zeroconf_lookup node["IpAddress"]
    end
  end

  def zeroconf_lookup(addr)
    addr = (IPAddr.new addr).to_s # sanity check
    out = `dig +time=1 +noall +additional +answer -x #{addr} @224.0.0.251 -p 5353`.lines.map(&:chomp).map do |line|
      (line.split "\t").last
    end
    out = out.join "\n"
    return "" if out.match /^;/
    out
  end

  def host_lookup(addr)
    unless @hosts
      @hosts = {}
      (File.readlines './hosts').map(&:chomp).each do |line|
        next if line.chars[0] == '#'
        parts = line.split ' ',2
        @hosts[parts[0]] = parts[1]
      end
    end
    return @hosts.fetch addr, nil
  end

  def mac_lookup(addr)
    addr = addr.gsub ':',''
    addr = addr.chars.slice(0,6).join
    unless @macs
      @macs = {}
      (File.readlines '/usr/local/share/nmap/nmap-mac-prefixes').map(&:chomp).each do |line|
        next if line.chars[0] == '#'
        parts = line.split ' '
        @macs[parts[0]] = parts[1]
      end
    end
    return @macs.fetch addr, ''
  end

end