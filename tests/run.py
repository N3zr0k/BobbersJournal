import os
import lupa, sys
flavor = sys.argv[1]
l = lupa.LuaRuntime(unpack_returned_tuples=True)
l.globals().FLAVOR = flavor
l.globals().ADDON_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'BobbersJournal'))
res = l.execute(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mock.lua')).read())
errs = res['errors']
print(flavor, 'errors:', len(errs))
for i in range(1, len(errs)+1): print(' ', errs[i])
sys.exit(1 if len(errs) else 0)
