import json, subprocess, sys, urllib.parse

BASE = "https://developer.apple.com/tutorials/data/documentation/"

def fetch(path):
    url = BASE + path + ".json"
    r = subprocess.run(["curl","-sL","-A","Mozilla/5.0",url], capture_output=True)
    try:
        return json.loads(r.stdout.decode("utf-8","replace"))
    except Exception:
        return None

def txt(items):
    o = ""
    for i in items or []:
        t = i.get("type")
        if t == "text": o += i.get("text","")
        elif t == "codeVoice": o += "`"+i.get("code","")+"`"
        elif t == "reference": o += str(i.get("identifier","")).split("/")[-1]
        elif t in ("emphasis","strong"): o += txt(i.get("inlineContent"))
        elif t == "paragraph": o += txt(i.get("inlineContent"))
    return o

def show(path):
    d = fetch(path)
    print("#### " + path)
    if not d:
        print("   !! FETCH FAIL / NOT FOUND\n"); return
    md = d.get("metadata",{})
    print("   TITLE:", md.get("title"), "| ROLE:", md.get("roleHeading"))
    for p in md.get("platforms") or []:
        flags = []
        if p.get("beta"): flags.append("BETA")
        if p.get("deprecated"): flags.append("DEPRECATED@"+str(p.get("deprecatedAt")))
        print("   PLAT:", p.get("name"), "introduced", p.get("introducedAt"), " ".join(flags))
    for sec in d.get("primaryContentSections",[]) or []:
        k = sec.get("kind")
        if k == "declarations":
            for dec in sec.get("declarations",[]):
                print("   DECL:", "".join(t.get("text","") for t in dec.get("tokens",[])))
        if k == "content":
            for c in sec.get("content",[]):
                if c.get("type") == "paragraph":
                    s = txt(c.get("inlineContent"))
                    if s.strip(): print("   DOC:", s)
                elif c.get("type") == "aside":
                    inner = " ".join(txt(x.get("inlineContent")) for x in c.get("content",[]) if x.get("type")=="paragraph")
                    print("   ASIDE["+str(c.get("style"))+"]:", inner)
    ab = d.get("abstract")
    if ab: print("   ABSTRACT:", txt(ab))
    print()

if __name__ == "__main__":
    for p in sys.argv[1:]:
        show(p)
