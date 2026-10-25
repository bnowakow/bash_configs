"""Append non-sensitive migration milestones; never log stdin or Secret data."""
from datetime import datetime,timezone
from pathlib import Path
import os,sys
LOG=Path(__file__).resolve().parent/'ACTIONS.log'
def log(message):
 line=datetime.now(timezone.utc).isoformat(timespec='seconds')+' '+message+'\n'
 fd=os.open(LOG,os.O_WRONLY|os.O_CREAT|os.O_APPEND,0o644)
 try:os.write(fd,line.encode());os.fsync(fd)
 finally:os.close(fd)
if __name__=='__main__':log(' '.join(sys.argv[1:]))
