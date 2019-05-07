import asyncio
import datetime
import os
import sys
import websockets


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


async def stdin_to_amplifier(amplifier, loop):
	reader = await stdin(loop)
	while True:
		amplifier.send((await reader.readline()).decode('utf-8').strip())


class MessageAmplifier:
	def __init__(self):
		self.queues = {}

	def register(self, websocket):
		self.queues[websocket] = asyncio.Queue(maxsize = 1000)
		return self.queues[websocket]

	def send(self, message):
		for queue in self.queues.values():
			try:
				queue.put_nowait(message)
			except asyncio.QueueFull:
				# Pop one, try again; it should be impossible for this to fail, so no try/except here.
				queue.get_nowait()
				queue.put_nowait(message)

	def unregister(self, websocket):
		del self.queues[websocket]


async def websocket_server(amplifier, websocket, path):
	queue = amplifier.register(websocket)
	try:
		while True:
			await websocket.send(await queue.get())
	except websockets.exceptions.ConnectionClosed: # Silence connection closures
		pass
	finally:
		amplifier.unregister(websocket)


async def print_status(amplifier):
	previousUtime = None
	while True:
		currentUtime = os.times().user
		cpu = (currentUtime - previousUtime) / 60 * 100 if previousUtime is not None else float('nan')
		print(f'{datetime.datetime.now():%Y-%m-%d %H:%M:%S} - {len(amplifier.queues)} clients, {sum(q.qsize() for q in amplifier.queues.values())} total queue size, {cpu:.1f} % CPU, {get_rss()/1048576:.1f} MiB RSS')
		if DEBUG:
			for socket in amplifier.queues:
				print(f'  {socket.remote_address}: {amplifier.queues[socket].qsize()}')
		previousUtime = currentUtime
		await asyncio.sleep(60)


def main():
	amplifier = MessageAmplifier()
	start_server = websockets.serve(lambda websocket, path: websocket_server(amplifier, websocket, path), None, 4568)
	loop = asyncio.get_event_loop()
	loop.run_until_complete(start_server)
	loop.run_until_complete(asyncio.gather(stdin_to_amplifier(amplifier, loop), print_status(amplifier)))


if __name__ == '__main__':
	main()
