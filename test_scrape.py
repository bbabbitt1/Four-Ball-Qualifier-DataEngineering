"""python test_scrape.py — offline checks for the Golf Genius parser and course ids."""
from scrape import course_id, parse_gg, platform

ROW = """<table><thead><tr><th>Pos.</th><th>Players</th><th>To Par</th><th>Total</th><th>Details</th></tr></thead>
<tr class="aggregate-row" data-aggregate-id="42" data-aggregate-name="A One / B Two">
 <td class="pos">CUT</td>
 <td class="name"><div class="team hidden">
   <div><a>A One</a><div class="affiliation">Boston, MA</div></div>
   <div><a>B Two</a><div class="affiliation">Newport, RI</div></div></div>
   <div class="player"><a>A One / B Two</a><div class="affiliation">Boston, MA, Newport, RI</div></div></td>
 <td>-7</td><td>65</td><td>1st Alternate</td></tr>
<tr class="expanded hidden"><td colspan="5"></td></tr></table>"""

rows = parse_gg(ROW)
assert len(rows) == 1, rows
r = rows[0]
assert (r["Pos."], r["Players"], r["To Par"], r["Total"], r["Details"]) == ("CUT", "A One / B Two", "-7", "65", "1st Alternate"), r
assert (r["player1"], r["player1_from"], r["player2"], r["player2_from"]) == ("A One", "Boston, MA", "B Two", "Newport, RI"), r
assert r["gg_aggregate_id"] == "42"
assert course_id("Dataw Island Club (Cotton Dike Course)", "SC") == "dataw-island-club-cotton-dike-course-sc"
assert platform("https://iga.bluegolf.com/x") == "bluegolf" and platform("scga-x.golfgenius.com") == "golfgenius" and platform("") is None
print("ok")
