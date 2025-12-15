import asyncio
from bleak import BleakClient

address = "D1:81:23:02:83:E7"  # replace with your Shimmer MAC
async def test():
    async with BleakClient(address) as client:
        print(await client.is_connected())

asyncio.run(test())