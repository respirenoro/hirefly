# Builds the practice dataset in assets/content/datasets (fictional, deterministic).
#
# Tables match the SQL lessons: pharmacies, pharmacists, shifts, assignments,
# plus tickets for the Excel, Power BI and ticket-process labs.
# Run: python tool/make_dataset.py
import csv
import datetime as dt
import pathlib
import random

random.seed(20261111)
out = pathlib.Path(__file__).resolve().parent.parent / 'assets' / 'content' / 'datasets'
out.mkdir(parents=True, exist_ok=True)

cities = [('Orlando', 'FL'), ('Sanford', 'FL'), ('Tampa', 'FL'), ('Jacksonville', 'FL'), ('Miami', 'FL'), ('Ocala', 'FL'),
          ('Savannah', 'GA'), ('Atlanta', 'GA'), ('Mobile', 'AL'), ('Charleston', 'SC')]
brands = ['Harbor', 'Lakeside', 'Citrus', 'Palmetto', 'Bayview', 'Magnolia', 'Coastal', 'Pinecrest', 'Riverbend', 'Sunrise']
kinds = ['Pharmacy', 'Drugs', 'Apothecary', 'Community Pharmacy', 'Rx']
pharmacies = []
for i in range(1, 41):
    city, state = random.choice(cities)
    pharmacies.append([i, f'{random.choice(brands)} {random.choice(kinds)} #{100 + i}', city, state])

first = ['Ana', 'Marcus', 'Priya', 'Daniel', 'Keisha', 'Tom', 'Lucia', 'Wei', 'Omar', 'Grace', 'Hector', 'Nadia', 'Sam', 'Ivy', 'Leon',
         'Maya', 'Victor', 'Rosa', 'Eli', 'June', 'Carlos', 'Tessa', 'Andre', 'Noor', 'Felix']
last = ['Reyes', 'Bennett', 'Shah', 'Okafor', 'Lindqvist', 'Moreno', 'Chen', 'Haddad', 'Whitaker', 'Diaz', 'Novak', 'Brooks',
        'Castillo', 'Ito', 'Mensah', 'Fischer', 'Alvarez', 'Park', 'Dubois', 'Grant']
pharmacists, used = [], set()
while len(pharmacists) < 60:
    name = f'{random.choice(first)} {random.choice(last)}'
    if name in used:
        continue
    used.add(name)
    pharmacists.append([10 + len(pharmacists), name, random.choices(['FL', 'GA', 'AL', 'SC'], [6, 2, 1, 1])[0],
                        random.choices([1, 0], [9, 1])[0]])
active = [p[0] for p in pharmacists if p[3] == 1]


def stamp(d):
    return d.strftime('%Y-%m-%d %H:%M:%S')


shifts, assignments = [], []
start = dt.datetime(2026, 1, 5)
sid, aid = 1000, 5000
for day in range(0, 270):
    date = start + dt.timedelta(days=day)
    month = date.month
    # Demand rises through the year; weekends are busier.
    n = random.randint(2, 4) + (1 if date.weekday() >= 5 else 0) + (1 if month >= 6 else 0)
    for _ in range(n):
        sid += 1
        pharmacy = random.choice(pharmacies)[0]
        emergency = random.random() < 0.18
        lead_hours = random.uniform(2, 10) if emergency else random.uniform(24, 24 * 9)
        starts = date.replace(hour=random.choice([7, 8, 9, 13, 14]), minute=0)
        requested = starts - dt.timedelta(hours=lead_hours)
        # Emergency requests fill faster after the alert feature (June).
        base = (0.6 if month >= 6 else 1.6) if emergency else (9 if month >= 6 else 14)
        fill_hours = max(0.1, random.gauss(base, base / 2.5))
        roll = random.random()
        if day >= 262 and roll < 0.5:
            status, reason, pharmacist, filled = 'open', '', '', ''
        elif roll < 0.07 or (fill_hours > lead_hours and roll < 0.6):
            status, reason, pharmacist, filled = 'cancelled', 'no coverage', '', ''
        elif roll < 0.13:
            status, reason = 'cancelled', 'pharmacy cancelled'
            if random.random() < 0.5:
                pharmacist, filled = '', ''
            else:
                pharmacist, filled = random.choice(active), stamp(requested + dt.timedelta(hours=min(fill_hours, lead_hours * 0.8)))
        elif roll < 0.19:
            status, reason = 'cancelled', 'pharmacist cancelled'
            pharmacist, filled = random.choice(active), stamp(requested + dt.timedelta(hours=min(fill_hours, lead_hours * 0.8)))
        else:
            status, reason = 'completed', ''
            pharmacist, filled = random.choice(active), stamp(requested + dt.timedelta(hours=min(fill_hours, lead_hours * 0.9)))
        shifts.append([sid, pharmacy, pharmacist, stamp(requested), filled, stamp(starts), status, reason, 1 if emergency else 0])
        if pharmacist != '':
            aid += 1
            done = stamp(starts + dt.timedelta(hours=random.choice([8, 8, 9, 10]))) if status == 'completed' else ''
            assignments.append([aid, sid, pharmacist, status, done])

categories = [('How do I', 0.42), ('Bug', 0.2), ('Access', 0.14), ('Feature request', 0.12), ('Data fix', 0.12)]
topics = {
    'How do I': ['How do I repost a cancelled shift', 'Where do I see who accepted a request', 'How do I change a shift start time',
                 'How do I export the monthly assignments', 'How do I add a new pharmacy location'],
    'Bug': ['Shift does not appear on the roster after saving', 'Alert was not sent to nearby pharmacists',
            'Schedule shows the wrong time zone', 'Duplicate assignment created on double click', 'Report total does not match the roster'],
    'Access': ['New dispatcher cannot log in', 'Password reset email not received', 'User needs manager permissions'],
    'Feature request': ['Filter roster by license state', 'Text message when a shift is filled', 'Bulk upload of shift requests'],
    'Data fix': ['Pharmacist listed twice', 'Wrong pharmacy address', 'Assignment logged against the wrong shift'],
}
tickets = []
tid = 20000
for day in range(0, 270):
    date = start + dt.timedelta(days=day)
    if date.weekday() >= 5 and random.random() < 0.7:
        continue
    for _ in range(random.randint(2, 6)):
        cat = random.choices([c for c, _ in categories], [w for _, w in categories])[0]
        # "How do I" tickets drop after the documentation rewrite in May.
        if cat == 'How do I' and date.month >= 5 and random.random() < 0.72:
            continue
        tid += 1
        opened = date.replace(hour=random.randint(8, 17), minute=random.randint(0, 59))
        sev = random.choices(['low', 'medium', 'high', 'critical'], [5, 4, 2, 1] if cat == 'Bug' else [7, 3, 1, 0])[0]
        hours = {'low': 30, 'medium': 16, 'high': 6, 'critical': 2}[sev] * random.uniform(0.3, 2.2)
        is_open = day >= 264 and random.random() < 0.5
        tickets.append([tid, stamp(opened), '' if is_open else stamp(opened + dt.timedelta(hours=hours)), random.choice(pharmacies)[0],
                        cat, sev, 'open' if is_open else 'closed', random.choice(topics[cat])])

tables = {
    'pharmacies': (['id', 'name', 'city', 'state'], pharmacies),
    'pharmacists': (['id', 'name', 'license_state', 'active'], pharmacists),
    'shifts': (['id', 'pharmacy_id', 'pharmacist_id', 'requested_at', 'filled_at', 'starts_at', 'status', 'cancel_reason', 'is_emergency'], shifts),
    'assignments': (['id', 'shift_id', 'pharmacist_id', 'status', 'completed_at'], assignments),
    'tickets': (['id', 'opened_at', 'closed_at', 'pharmacy_id', 'category', 'severity', 'status', 'title'], tickets),
}
types = {
    'pharmacies': 'id INT PRIMARY KEY, name VARCHAR(80), city VARCHAR(40), state CHAR(2)',
    'pharmacists': 'id INT PRIMARY KEY, name VARCHAR(80), license_state CHAR(2), active INT',
    'shifts': 'id INT PRIMARY KEY, pharmacy_id INT, pharmacist_id INT, requested_at DATETIME, filled_at DATETIME, starts_at DATETIME, status VARCHAR(20), cancel_reason VARCHAR(40), is_emergency INT',
    'assignments': 'id INT PRIMARY KEY, shift_id INT, pharmacist_id INT, status VARCHAR(20), completed_at DATETIME',
    'tickets': 'id INT PRIMARY KEY, opened_at DATETIME, closed_at DATETIME, pharmacy_id INT, category VARCHAR(30), severity VARCHAR(10), status VARCHAR(10), title VARCHAR(120)',
}


def lit(v):
    if v == '':
        return 'NULL'
    return str(v) if isinstance(v, int) else "'" + str(v).replace("'", "''") + "'"


sql = ['-- HireFly practice data (fictional). Runs as-is in SQLite and SQL Server.']
for name, (cols, rows) in tables.items():
    with open(out / f'{name}.csv', 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(cols)
        w.writerows(rows)
    sql.append(f'CREATE TABLE {name} ({types[name]});')
    for i in range(0, len(rows), 400):
        chunk = ',\n'.join('(' + ', '.join(lit(v) for v in r) + ')' for r in rows[i:i + 400])
        sql.append(f'INSERT INTO {name} ({", ".join(cols)}) VALUES\n{chunk};')
(out / 'practice.sql').write_text('\n'.join(sql) + '\n', encoding='utf-8')
print({k: len(v[1]) for k, v in tables.items()})
