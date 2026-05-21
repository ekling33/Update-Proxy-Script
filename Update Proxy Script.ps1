.mdb / .accdb Access files
→ Migrate the data to SQL Server and change Blue Prism connections from Microsoft.Jet.OLEDB.4.0 / Microsoft.ACE.OLEDB.12.0 to a SQL‑based provider (e.g., SQL Server Native Client / ODBC).

Excel files read via ACE
→ Stop using Microsoft.ACE.OLEDB for Excel and instead read Excel via Blue Prism Excel VBO / .NET libraries (e.g., EPPlus / ClosedXML) or 64‑bit ODBC drivers.

CSV files read via ACE‑style “table”
→ Replace the ACE‑based CSV connection with Blue Prism’s native CSV‑parsing actions or a .NET‑based CSV helper, then remove ACE‑2016‑based drivers.

Legacy .mdb that must stay .mdb
→ Keep the .mdb‑to‑ACE logic in a separate 32‑bit helper app (using ACE.OLEDB) and make Blue Prism talk to that app over API / SQL‑style endpoints instead of directly to the .mdb.

Mixed datasets (.mdb/Excel/CSV)
→ For all mixed‑data teams, remove any Microsoft.Jet.OLEDB.4.0 / ACE.OLEDB.12.0‑based connections, migrate data to SQL where possible, and route everything through SQL‑based, ODBC‑based, or API‑based Blue Prism connections.
