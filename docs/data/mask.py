# Masks what Decidim itself changes on every request, so two fetches of one
# page can be compared: the CSRF tokens, the links to stored files (signed
# anew on each render), the spam trap's random field names, and the script tag
# of the profiler that the development app carries, and the random ids
# Decidim gives its filter forms.
import re, sys
h = sys.stdin.read()
h = re.sub(r'(name="csrf-token" content=")[^"]*', r'\1MASKED', h)
h = re.sub(r'(name="authenticity_token" value=")[^"]*', r'\1MASKED', h)
h = re.sub(r'<script async nonce="[^"]*" type="text/javascript" id="mini-profiler"[^>]*></script>', '<!-- mini-profiler -->', h)
h = re.sub(r'/rails/active_storage/[^"\'\s)]+', '/rails/active_storage/MASKED', h)
h = re.sub(r'<style media="screen">\.[\w-]+_\d+ \{[^}]*\}</style>', '<style media="screen">SPAMTRAP</style>', h)
h = re.sub(r'<div class="[\w-]+_\d+"><label for="[\w-]+">(.*?)</label><input type="text" name="[\w-]+" id="[\w-]+"', r'<div class="SPAMTRAP"><label>\1</label><input type="text" name="SPAMTRAP"', h)
h = re.sub(r'(name="spinner" value=")[^"]*', r'\1MASKED', h)
h = re.sub(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'UUID', h)
h = re.sub(r'panel-view-more-[0-9a-f]{8}', 'panel-view-more-ID', h)
sys.stdout.write(h)
