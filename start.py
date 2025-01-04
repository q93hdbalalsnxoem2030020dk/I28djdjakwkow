import os
import sys

menu = """
1. backup-all
2. restore
3. start

note: Integral, choose only (1-3)
"""

print(menu)
try:
    nrl = int(input("opt > "))
except ValueError:
    print("Please enter a valid option (1-3).")
    sys.exit(1)

if nrl == 1:
    os.system('mkdir -p $HOME/.backup_neural; cp -r $HOME/_neural.ai $HOME/.backup_neural')
elif nrl == 2:
    os.system('rm -rf $HOME/_neural.ai; cp -r $HOME/.backup_neural/_neural.ai $HOME')
    print("[neural_process] Restored.")
elif nrl == 3:
    os.system('npm audit fix')
    os.system('node $PWD/.data/_neural.mjs')
else:
    print("Invalid option. Please choose between 1 and 3.")