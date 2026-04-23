#!/usr/bin/env python3
import json
import sys

def main() -> None:
    path = sys.argv[1]
    d = json.load(open(path))
    it = d.get("data", {}).get("itinerary")
    if not it:
        print("NO ITINERARY")
        return
    items = it["items"]
    total_cost = it["totalCost"]
    print(f"total stops={len(items)} cost={total_cost} EUR")
    by_day = {}
    for x in items:
        by_day.setdefault(x["dayIndex"], []).append(x)
    for d_idx in sorted(by_day):
        print(f"\n-- day {d_idx} --")
        for x in by_day[d_idx]:
            h = x["startMinutes"] // 60
            m = x["startMinutes"] % 60
            hm = f"{h:02d}:{m:02d}"
            leg = ""
            if x["travelFromPrev"]:
                opts = x["travelFromPrev"]["options"]
                leg_str = " | ".join(
                    f"{o['mode'][:5]} {o['minutes']}m {o['costEur']}EUR"
                    for o in opts
                )
                leg = " [legs: " + leg_str + "]"
            note = x.get("note")
            note_str = f" ({note})" if note else ""
            title = x["title"][:45]
            cat = x["category"]
            cost = x["costEur"]
            print(f"  {hm}  {cat:10s}  {title:45s}  ~{cost}EUR{note_str}{leg}")

if __name__ == "__main__":
    main()
