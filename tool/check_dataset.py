# Loads the practice data into SQLite and prints the trends the labs rely on.
# Run: python tool/check_dataset.py
import pathlib
import sqlite3

sql = (pathlib.Path(__file__).resolve().parent.parent / 'assets' / 'content' / 'datasets' / 'practice.sql').read_text(encoding='utf-8')
c = sqlite3.connect(':memory:')
c.executescript(sql)
print('shifts by status', c.execute('select status, count(*) from shifts group by 1').fetchall())
print('how-do-I tickets by month', c.execute("select strftime('%m', opened_at), sum(category = 'How do I'), count(*) from tickets group by 1").fetchall())
print('emergency hours to fill by month', c.execute(
    "select strftime('%m', requested_at), round(avg((julianday(filled_at) - julianday(requested_at)) * 24), 1) "
    'from shifts where is_emergency = 1 and filled_at is not null group by 1').fetchall())
