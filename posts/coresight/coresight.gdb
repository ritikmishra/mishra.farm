# GDB script that defines helper utilities for interacting with the ETM+ETB

# DWT register base addresses
set $DWTBASE = 0xE0001000
set $DWT_CTRL = 0xE0001000
set $DWT_CYCCNT = 0xE0001004

set $DWT_COMP0 = 0xE0001020
set $DWT_MASK0 = 0xE0001024
set $DWT_FUNCTION0 = 0xE0001028

set $DWT_COMP1 = 0xE0001030
set $DWT_MASK1 = 0xE0001034
set $DWT_FUNCTION1 = 0xE0001038

set $DWT_COMP2 = 0xE0001040
set $DWT_MASK2 = 0xE0001044
set $DWT_FUNCTION2 = 0xE0001048

set $DWT_COMP3 = 0xE0001050
set $DWT_MASK3 = 0xE0001054
set $DWT_FUNCTION3 = 0xE0001058

# ITM registers
set $ITMBASE = 0xE0000000

# ETB registers
set $ETBBASE = 0xE0042000
set $ETB_RDP = $ETBBASE + 0x004
set $ETB_STS = $ETBBASE + 0x00C
set $ETB_RRD = $ETBBASE + 0x010
set $ETB_RRP = $ETBBASE + 0x014
set $ETB_RWP = $ETBBASE + 0x018
set $ETB_TRG = $ETBBASE + 0x01C
set $ETB_CTL = $ETBBASE + 0x020
set $ETB_RWD = $ETBBASE + 0x024
set $ETB_FFSR = $ETBBASE + 0x300
set $ETB_FFCR = $ETBBASE + 0x304
set $ETB_LAR = $ETBBASE + 0xFB0
set $ETB_LSR = $ETBBASE + 0xFB4

# ETM registers
set $ETMBASE = 0xE0041000
set $ETM_CR = $ETMBASE + (4 * 0x000)
set $ETM_CCR = $ETMBASE + (4 * 0x001)
set $ETM_TRIGGER = $ETMBASE + (4 * 0x002)
set $ETM_SR = $ETMBASE + (4 * 0x004)
set $ETM_SCR = $ETMBASE + (4 * 0x005)
set $ETM_TSSCR = $ETMBASE + (4 * 0x006)
set $ETM_TECR2 = $ETMBASE + (4 * 0x007)
set $ETM_TEEVR = $ETMBASE + (4 * 0x008)
set $ETM_TECR1 = $ETMBASE + (4 * 0x009)
set $ETM_FFRR = $ETMBASE + (4 * 0x00A)
set $ETM_FFLR = $ETMBASE + (4 * 0x00B)
set $ETM_VDEVR = $ETMBASE + (4 * 0x00D)
set $ETM_VDCR1 = $ETMBASE + (4 * 0x00E)
set $ETM_VDCR3 = $ETMBASE + (4 * 0x00F)
set $ETM_LAR = $ETMBASE + (4 * 0x3EC)
set $ETM_LSR = $ETMBASE + (4 * 0x3ED)


define dwtSetupDmacTrace
  push_lang c
  
  printf "Setting up DWT trace for DMAC channels 4-5 (0x4100A080-0x4100A0A0)\n"
  
  # Configure comparator 0 for DMAC range
  set *($DWT_COMP0) = 0x4100A080
  set *($DWT_MASK0) = 5
  # FUNCTION = 0001 (PC trace + data value trace on RW), EMITRANGE = 0, DATAVMATCH = 0
  set *($DWT_FUNCTION0) = 0b011 | (0 << 5)
  
  printf "DWT Comp 0: address=0x%08x, mask=%d, function=0x%08x\n", *($DWT_COMP0), *($DWT_MASK0), *($DWT_FUNCTION0)
  
  pop_lang
end


define etbLock
  push_lang c

  printf "Locking ETB...\n"
  set *($ETB_LAR) = 0x00000000  
  printf "ETB Lock Status: 0x%08x\n", *($ETB_LSR)
end

define etbStatus
  push_lang c

  printf "ETB Status: 0x%08x\n", *($ETB_STS)
  printf "ETB Control: 0x%08x\n", *($ETB_CTL)
  printf "ETB Formatter/Flush Status: 0x%08x\n", *($ETB_FFSR)
  printf "ETB Formatter/Flush Control: 0x%08x\n", *($ETB_FFCR)
  printf "ETB Read Pointer: 0x%08x\n", *($ETB_RRP)
  printf "ETB Write Pointer: 0x%08x\n", *($ETB_RWP)

  pop_lang
end

define etbUnlock
  set *($ETB_LAR) = 0xC5ACCE55
end

define etbResetPointers
  set *($ETB_RWP) = 0
  set *($ETB_RRP) = 0
end

define etbEnable

  etbUnlock
  etbResetPointers

  # Trigger level = 0 -> treat the ETB like a trace FIFO
  set *($ETB_TRG) = 0x0
 
  # Disable formatting
  set *($ETB_FFCR) = 0b00

  # Enable tracing
  set *($ETB_CTL) = 1

end

define etbDisable
  etbUnlock
  set *($ETB_CTL) = 0
end

python
import gdb
import struct

class EtbDumpCommand(gdb.Command):
    """Dump the full ETB circular buffer to a file: etbDump <filename>"""

    def __init__(self):
        super(EtbDumpCommand, self).__init__("etbDump", gdb.COMMAND_USER)

    def invoke(self, arg, from_tty):
        filename = arg.strip()
        if not filename:
            print("Usage: etbDump <filename>")
            return

        gdb.execute("etbDisable")
        gdb.execute("set language rust") 
        # Get current write pointer (in bytes)
        depth_words = int(gdb.parse_and_eval('*($ETB_RDP as *const u32)'))
        write_ptr_bytes = int(gdb.parse_and_eval('*($ETB_RWP as *const u32)'))
        write_index = write_ptr_bytes % depth_words

        print(f"ETB write pointer: {write_ptr_bytes} bytes (word index {write_index})")

        # The oldest word is at write_index + 1 (mod DEPTH)
        start_index = (write_index + 1) % depth_words

        print(f"Dumping {depth_words * 4} bytes (full buffer) starting from index {start_index}")

        data = bytearray()

        # Reset read pointer
        gdb.execute(f'set *($ETB_RRP as *const u32) = {start_index}')

        # Read out from start_index..depth_words 
        for _ in range(start_index, depth_words):
            word_val = int(gdb.parse_and_eval('*($ETB_RRD as *const u32)'))
            data.extend(struct.pack('<L', word_val))

        gdb.execute(f'set *($ETB_RRP as *const u32) = {0}')

        # Now read out DEPTH_WORDS words in order
        for i in range(0, start_index):
            word_val = int(gdb.parse_and_eval('*($ETB_RRD as *const u32)'))
            data.extend(struct.pack('<L', word_val))

        with open(filename, 'wb') as f:
            f.write(data)

        print(f"Wrote {len(data)} bytes to {filename}")

        gdb.execute("set language auto")

EtbDumpCommand()
end

define etmEnableBasic
  # Set programming bit + power on
  set *($ETM_CR) |= 0x00000400
  set *($ETM_CR) |= 0x00000400

  # Set TRIGGER to always be false
  set *($ETM_TRIGGER) = 0x406f

  # Set TRACEENABLE to always be true
  set *($ETM_TEEVR) = 0x6f

  # Configure trace enable (trace all instructions)
  set *($ETM_TECR1) = 0x01000000

  # Enable ETM and clear programming bit
  set *($ETM_CR) = (0x00000010) | (1 << 8)
end

define ITMTXEna
  push_lang c

  if (($argc!=1) || ($arg0<0) || ($arg0>1))
    help ITMTXEna
  else
    set *($ITMBASE+0xfb0) = 0xc5acce55
    if ($arg0==0)
      set *($ITMBASE+0xe80) &= ~(0x1<<3)
    else
      set *($ITMBASE+0xe80) |= (($arg0&1)<<3)
    end
  end

  pop_lang
end
document ITMTXEna
ITMTXEna <0|1> 0-DWT packets are not forwarded to the ITM
               1-DWT packets are output to the ITM
end

define ITMEna
  push_lang c

  if (($argc!=1) || ($arg0<0) || ($arg0>1))
    help ITMEna
  else
    set *($ITMBASE+0xfb0) = 0xc5acce55
    if ($arg0==0)
      set *($ITMBASE+0xe80) &= ~(0x1<<0)
    else
      set *($ITMBASE+0xe80) |= (($arg0&1)<<0)
    end
  end

  pop_lang
end
document ITMEna
ITMEna <0|1> Master Enable for ITM
end