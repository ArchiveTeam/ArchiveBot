# Tests whether dnspython's is_multicast is broken. Compatible with dnspython 1.15 and 1.16; patches internals of dnspython and so may easily break on other versions.
# Relevant issues: https://github.com/ArchiveTeam/wpull/issues/365 https://github.com/rthalley/dnspython/issues/302


import dns.query
import dns.rcode
import dns.resolver
import socket
import sys


def nowait(*args):
	pass


class TriggerSocket(socket.socket):
	'''A socket that triggers dnspython's ValueError crash'''
	def __init__(self, *args, **kwargs):
		super().__init__(*args, **kwargs)
		self.__targetAddress = None
		self.__query = None
		self.__recvCount = 0

	def sendto(self, data, destination):
		self.__query = dns.message.from_wire(data)
		self.__targetAddress = destination

	def recvfrom(self, bufsize):
		self.__recvCount += 1
		if self.__recvCount == 1:
			# First call, return bogus multicast
			return b'fuckyou', ('255.255.255.255', 12345)
		else:
			# Second or later call, return NXDOMAIN
			r = dns.message.make_response(self.__query)
			r.set_rcode(dns.rcode.NXDOMAIN)
			return r.to_wire(), self.__targetAddress


def test():
	origWaitReadable = dns.query._wait_for_readable
	dns.query._wait_for_readable = nowait
	origWaitWritable = dns.query._wait_for_writable
	dns.query._wait_for_writable = nowait
	origSocketFactory = dns.query.socket_factory
	dns.query.socket_factory = TriggerSocket
	try:
		# With ignore_unexpected = True, this would return the NXDOMAIN response, but dnspython doesn't set that by default.
		# This means that dns.query.udp raises a dns.query.UnexpectedSource exception instead of handling the actual response and returning NXDOMAIN.
		# But at least it shouldn't crash with a ValueError...
		dns.query.udp(dns.message.make_query('example.org', 'A'), '1.1.1.1')
	except dns.query.UnexpectedSource:
		return True
	except ValueError:
		return False
	finally:
		dns.query._wait_for_readable = origWaitReadable
		dns.query._wait_for_writable = origWaitWritable
		dns.query.socket_factory = origSocketFactory


if __name__ == '__main__':
	sys.exit(int(not test())) # True, indicating a successful test, becomes False, and int(False) = 0. Similarly, False becomes 1.
