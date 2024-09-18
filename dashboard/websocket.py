import asyncio
import collections
import datetime
import io
import os
import sys
import websockets
import websockets.extensions.permessage_deflate
import websockets.framing


DEBUG = 'WSDEBUG' in os.environ and os.environ['WSDEBUG'] == '1'


# Taken from qwarc.utils
PAGESIZE = os.sysconf('SC_PAGE_SIZE')
def get_rss():
	with open('/proc/self/statm', 'r') as fp:
		return int(fp.readline().split()[1]) * PAGESIZE


async def stdin(loop):
	reader = asyncio.StreamReader(limit = 2 ** 20) # 1 MiB buffer limit
	reader_protocol = asyncio.StreamReaderProtocol(reader)
	await loop.connect_read_pipe(lambda: reader_protocol, sys.stdin)
	return reader


async def stdin_to_amplifier(amplifier, loop, stats):
	reader = await stdin(loop)
	while True:
		d = await reader.readline()
		stats['stdin read'] += len(d)
		amplifier.send(d.decode('utf-8').strip())


def websocket_extensions_to_key(extensions):
	# Convert a list of websockets extensions into a key, handling PerMessageDeflate objects with the relevant care for server-side compression dedupe
	def _inner():
		for e in extensions:
			if isinstance(e, websockets.extensions.permessage_deflate.PerMessageDeflate) and e.local_no_context_takeover:
				yield (websockets.extensions.permessage_deflate.PerMessageDeflate, e.remote_max_window_bits, e.local_max_window_bits, tuple(e.compress_settings.items()))
			else:
				yield e
	return tuple(_inner())


class MessageAmplifier:
	def __init__(self, stats):
		self.queues = {}  # websocket -> queue
		self._stats = stats

	def register(self, websocket):
		q = asyncio.Queue(maxsize = 1000)
		self.queues[websocket] = q
		return q

	def send(self, message):
		#FIXME This abuses internal API of websockets==7.0
		# Using the normal `websocket.send` reencodes and recompresses the message for every client.
		# So we construct the relevant Frame once instead and push that to the individual queues.
		frame = websockets.framing.Frame(fin = True, opcode = websockets.framing.OP_TEXT, data = message.encode('utf-8'))
		data = {}  # tuple of extensions key → bytes
		for websocket, queue in self.queues.items():
			extensionsKey = websocket_extensions_to_key(websocket.extensions)
			if extensionsKey not in data:
				output = io.BytesIO()
				frame.write(output.write, mask = False, extensions = websocket.extensions)
				data[extensionsKey] = output.getvalue()
				self._stats['frame writes'] += len(data[extensionsKey])
			try:
				queue.put_nowait(data[extensionsKey])
			except asyncio.QueueFull:
				# Pop one, try again; it should be impossible for this to fail, so no try/except here.
				dropped = queue.get_nowait()
				self._stats['dropped'] += len(dropped)
				queue.put_nowait(data[extensionsKey])

	def unregister(self, websocket):
		del self.queues[websocket]


async def websocket_server(amplifier, websocket, path, stats):
	queue = amplifier.register(websocket)
	try:
		while True:
			#FIXME See above; this is write_frame essentially
			data = await queue.get()
			await websocket.ensure_open()
			websocket.writer.write(data)
			stats['sent'] += len(data)
			if websocket.writer.transport is not None:
				if websocket.writer_is_closing():
					await asyncio.sleep(0)
			try:
				async with websocket._drain_lock:
					await websocket.writer.drain()
			except ConnectionError:
				websocket.fail_connection()
				await websocket.ensure_open()
	except websockets.exceptions.ConnectionClosed: # Silence connection closures
		pass
	finally:
		amplifier.unregister(websocket)


async def print_status(amplifier, stats):
	interval = 60
	previousUtime = None
	previousStats = {}
	while True:
		currentUtime = os.times().user
		cpu = (currentUtime - previousUtime) / interval * 100 if previousUtime is not None else float('nan')
		print(f'{datetime.datetime.now():%Y-%m-%d %H:%M:%S} - ' +
			', '.join([
				f'{len(amplifier.queues)} clients',
				f'{sum(q.qsize() for q in amplifier.queues.values())} total queue size',
				f'{cpu:.1f} % CPU',
				f'{get_rss()/1048576:.1f} MiB RSS',
				'throughput: ' + ', '.join(f'{(stats[k] - previousStats.get(k, 0))/interval/1000:.1f} kB/s {k}' for k in stats),
			])
		)
		if DEBUG:
			for socket in amplifier.queues:
				print(f'  {socket.remote_address}: {amplifier.queues[socket].qsize()}')
		previousUtime = currentUtime
		previousStats.update(stats)
		await asyncio.sleep(interval)


def main():
	stats = {'stdin read': 0, 'frame writes': 0, 'sent': 0, 'dropped': 0}
	amplifier = MessageAmplifier(stats)
	# Disable context takeover (cf. RFC 7692) so the compression can be reused
	start_server = websockets.serve(
		lambda websocket, path: websocket_server(amplifier, websocket, path, stats),
		None,
		4568,
		extensions = [websockets.extensions.permessage_deflate.ServerPerMessageDeflateFactory(server_no_context_takeover = True)]
	)
	loop = asyncio.get_event_loop()
	loop.run_until_complete(start_server)
	loop.run_until_complete(asyncio.gather(stdin_to_amplifier(amplifier, loop, stats), print_status(amplifier, stats)))


if __name__ == '__main__':
	main()
