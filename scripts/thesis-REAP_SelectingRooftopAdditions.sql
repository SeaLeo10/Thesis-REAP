--Load Baugenehmigungen CSV into "Thesis" database.
DROP TABLE public.baugenehmigungen;
CREATE TABLE public.baugenehmigungen
(
    nummer             		varchar(800),
	title              		varchar(800),
	publishingdate     		varchar(40),
	author             		varchar(200),
	tags               		varchar(400),
	"id"               		varchar(100),
	filereference      		varchar(40),
	flurstueck         		varchar(200),
	gemarkung          		varchar(200),
	baublock           		varchar(200),
	bebauungsplan      		varchar(200),
	baustufenplan      		varchar(200)
   );

COPY public.baugenehmigungen FROM '/Users/Shared/PostgreSQL_Data/baugenehmigungen2.csv' WITH (DELIMITER ';'); --, HEADER, FORMAT csv);

SELECT * FROM public.baugenehmigungen LIMIT 100;

--Add column to baugenehmigungen where "aufstockung" can be found in the title.
ALTER TABLE public.baugenehmigungen
ADD aufstockung boolean;
UPDATE public.baugenehmigungen
SET aufstockung = 'false';
UPDATE public.baugenehmigungen
SET aufstockung = 'true'
	WHERE LOWER(title) LIKE '%aufstockung%';

    
--Add column to baugenehmigungen where entries have a tag indicating the file
--refers to a Vorbescheid according to HBauO §63 (asking questions).
ALTER TABLE public.baugenehmigungen
ADD vorbescheid boolean;
UPDATE public.baugenehmigungen
SET vorbescheid = 'false'
UPDATE public.baugenehmigungen
SET vorbescheid = 'true'
	WHERE LOWER(tags) LIKE '%vorbescheid%';

--Add column to baugenehmigungen where entries have a tag indicating the file
--refers to a building permit according to HBauO §61 (simplified permitting process).
ALTER TABLE public.baugenehmigungen
ADD permit_vereinfacht boolean;
UPDATE public.baugenehmigungen
SET permit_vereinfacht = 'false'
UPDATE public.baugenehmigungen
SET permit_vereinfacht = 'true'
	WHERE tags LIKE '%61%';
    
--Add column to baugenehmigungen where entries have a tag indicating the file
--refers to a building permit according to HBauO §62 (normal process).
ALTER TABLE public.baugenehmigungen
ADD permit_normal boolean;
UPDATE public.baugenehmigungen
SET permit_normal = 'false'
UPDATE public.baugenehmigungen
SET permit_normal = 'true'
	WHERE tags LIKE '%62%';
    
--Add column to baugenehmigungen where entries have a tag indicating the file
--refers to a change to a building permit.
UPDATE public.baugenehmigungen
SET aenderungsbescheid = 'false'
UPDATE public.baugenehmigungen
	WHERE tags LIKE '%nderungsbescheid%';
    
--I know from later selections that one of the filereference numbers for a relevant
--permit (for my on-site data collection) contains a formatting error. Since 
--there is only one instance like this, I've decided to replace it manually. 
UPDATE public.baugenehmigungen
	SET filereference = 'W/WBZ/05506/2013'
	WHERE filereference = 'W/WBZ/05506/2013/Ä';

--To create a smaller table with only the possibly relevant 
--building permits for rooftop additons. Then, I can focus on filling in
--only the necessary information. My goal is not to fill in missing data for all
--building permits in the transparency portal.
CREATE TABLE public.aufstockung_permits AS 
SELECT 	title					AS title, 
        RIGHT(filereference, 4)	AS jahr,
        filereference			AS filereference,
        aufstockung				AS aufstockung, 
        flurstueck				AS flurstueck, 
        gemarkung				AS gemarkung, 
        baublock				AS baublock,
        bebauungsplan			AS bebauungsplan, 
        baustufenplan			AS baustufenplan,
       	vorbescheid				AS vorbescheid,
        permit_vereinfacht		AS permit_vereinfacht,
        permit_normal			AS permit_normal,
        aenderungsbescheid		AS aenderungsbescheid,
        "id" 					AS "id"
FROM public.baugenehmigungen
WHERE 	aufstockung = 'true'
ORDER BY jahr DESC;

--Now, I need to update the "gemarkung2" column in the rooftop addition building permit table
--so that entries in that have a baublock but do not have a Gemarkung are assigned a Gemarkung.
--This is a necessary preparatory step to be able to concatinate the Flurstück and Gemarkung columns
--to create an FSK (Flurstückskennzeichen) for every entry. That's how I will be able to map the
--building permits on the plot level.
--Add new column, gemarkung2, which I will use to fill in missing gemarkung information.
ALTER TABLE public.aufstockung_permits
ADD gemarkung2 varchar;
--Fill the column with the information from the column "gemarkung"
UPDATE 	public.aufstockung_permits
SET 	gemarkung2 = gemarkung;

--The flurstueck (plot) information is missing for a few of the entries.
--There are 22 rows with missing plot information in aufstockung_permits.flurstueck. 
--15 are distinct based on title,filereference, austockung, and gemarkung3. 
--Information on plots is missing for 6 of the distinct rows where aufstockung = 'true'
--Examine the data with the following selection:
SELECT DISTINCT
	auf.id,
	auf.flurstueck,
    auf.gemarkung2,
    auf.baublock,
    auf.title,
    auf.filereference,
    auf.aufstockung
FROM aufstockung_permits AS auf
WHERE auf.aufstockung = 'true' --AND flurstueck = ''
ORDER BY auf.flurstueck, auf.gemarkung2;

--I can manually fill in the missing information. I do this only for the rows
--in aufstockung_permits.aufstockung where aufstockung = 'true'. And for which I can
--reasonably discern to which plot the permit is referring. For 3 of the six, I could
--figure out the missing flurstuck number. Only one of the remaining 3 would be a
--relevant building (filereference: "A/WBZ/00830/2016"), the other two are clearly
--not relevant.
UPDATE aufstockung_permits
	SET flurstueck = '1805'
	WHERE filereference = 'M/BP/02510/2015';
UPDATE aufstockung_permits
	SET flurstueck = '1704'
	WHERE filereference = 'M/BP/01596/2016';
UPDATE aufstockung_permits
	SET flurstueck = '643'
	WHERE filereference = 'M/BP/00682/2016';

--Now that the plot information is as complete as possible,
--I need to examine the Gemarkung data.
--To add missing information into the gemarkung2 column 
--when baublock information is provided. I do a spatial join with the baublock
--and gemarkungungen datasets. Then, based on the given baublock information in 
--the transparenzportal datatable, I fill in the missing gemarkung data into gemarkung2 
--whenever there are empty fields. Because a couple of the entries have more than 
--one baublock provided, I take only the first 6 characters in baugenehmigungen.baublock.
--AIM: Create table that joins baublock with gemarkung number. 
--METHOD: Using ST_Contains and ST_PointOnSurface: select random point on the baublock polygon,
--join that with the Gemarkung information. ST_PointOnSurface takes a point that is garanteed to be
--within the polygon. ST_Centroid would be another option, but the centroid of a polygon is 
--not guaranteed to lie within the polygon (I checked, though, and the results are the same).
--To confirm that all baublocks have been assigned a Gemarkung, select count of all entries 
--in the resulting combined table and compare with number
--of entries in baublock table.

--CHOSEN APPROACH
--The folwoing table uses the ST_PointOnSurface method to assign the baublock a gemarkung. 
--The result: 8669 objects.
CREATE TABLE public.bbkgmk AS 
SELECT
		bbk.bblock AS bblock_no,
		gmk.name AS gmk_name,
        gmk.gemarkung_ AS gmk_no,
        bbk.geom AS geom
  FROM  public.gemarkungen AS gmk
  JOIN 	public.baublock AS bbk
  ON ST_Contains(gmk.geom, ST_PointOnSurface(bbk.geom))
SELECT * FROM public.bbkgmk --view the resulting new table

--NOT CHOSEN APPROACH
--Create a second table using the ST_Centroid method. The result: 8669 objects.
CREATE TABLE public.bbkgmk2 AS 
SELECT
		bbk.bblock AS bblock_no,
		gmk.name AS gmk_name,
        gmk.gemarkung_ AS gmk_no,
        bbk.geom AS geom
  FROM  public.gemarkungen AS gmk
  JOIN 	public.baublock AS bbk
  ON ST_Contains(gmk.geom, ST_Centroid(bbk.geom))
SELECT * FROM public.bbkgmk2 --view the resulting new table

--The following creates a table that can be imported to QGIS using the DB manager
--to see the baublocks that are affected by choosing the ST_centroid method vs. 
--the ST_PointOnSurface method. There is a difference of 48 records, but this 
--number would change each time the ST_PointOnSurface selection is run, since the 
--point is randomly selected.
CREATE TABLE public.bbkgmk3_testdifference AS 
SELECT 	bbkgmk.bblock_no AS bblock_no, 
		bbkgmk.gmk_name AS gmk_name, 
        bbkgmk2.bblock_no AS bblock_no2, 
        bbkgmk2.gmk_name AS gmk_name2,
        bbkgmk.geom
FROM public.bbkgmk
JOIN public.bbkgmk2
ON (bbkgmk.bblock_no) = (bbkgmk2.bblock_no)
WHERE (bbkgmk.gmk_name) <> (bbkgmk2.gmk_name);
--DROP TABLE public.bbkgmk3_testdifference; --Drop table after testing.

--Add missing values to gemarkung2 based on attribute join with bbkgmk.
--Fill in the missing information based on gemarkung assigned to the baublock. 
--Only the first baublock number (frist 6 digits) listed in the column 
--aufstockung_permits.baublock. 
UPDATE 	aufstockung_permits
SET 	gemarkung2 = b.gmk_name 
FROM 	bbkgmk AS b
WHERE (LEFT(aufstockung_permits.baublock,6) :: integer) = b.bblock_no;

--View the resulting columns:
SELECT	auf.gemarkung2,
        auf.baublock
FROM aufstockung_permits AS auf
ORDER BY gemarkung2;

--View the first 6 digits (the first baublock per permit)
SELECT
LEFT(auf.baublock,6) :: integer 
FROM aufstockung_permits AS auf;

--Look at the make-up of the aufstockung_permits.baublock column to 
--see how many of the entries has exactly one baublock listed and which 
--have more. 
---Results:	1217 have exactly 1 baublocks
---			26 have exactly 2 baublocks
---			4 have eactly 3 baublocks
---			2 have exactly 6 baublocks
SELECT
	COUNT(LENGTH(auf.baublock :: text)),
    LENGTH(auf.baublock :: text) AS baublock_len
FROM aufstockung_permits AS auf
GROUP BY length(auf.baublock :: text);

--This shows all the entries in the aufstockung_permits
--table where there is more than one baublock. There are 20
--distinct entries with a combination of title, filereference, and baublock.
--There are 32 entries total, which suggests there are multiple
--entries for the same project.
SELECT DISTINCT
	auf.baublock,
    auf.title,
    auf.filereference
FROM aufstockung_permits AS auf
WHERE ((length(auf.baublock :: text)) > 6);

--Selecting all distinct entries in table aufstockung_permits
--table whre there is exactly one baublock. There are
--996 distinct entries with a combination of title, filereference, and baublock.
--There are 1217 entries total (as shown above).
SELECT DISTINCT
	auf.baublock,
    auf.title,
    auf.filereference
FROM aufstockung_permits AS auf
WHERE ((length(auf.baublock :: text)) = 6);


--Join the the gemarkung name in aufstockung_permits 
--with the appropriate Gemarkung code.
--This is a necessary step to create the FSK for each plot, which can then 
--be plotted on a map.

--How many plots from each entry in aufstockung_permits should be included
--in the table of building permits for mapping?
--The following creates a table with the plots separated into different columns,
--I don't use this one for further analysis, but it's interesting to see.
SELECT	a.id										AS auf_id,
		g.gemarkung_ 								AS gem_no,
        split_part((a.flurstueck :: text),'|', 1)	AS auf_plot1,
        split_part((a.flurstueck :: text),'|', 2) 	AS auf_plot2,
        split_part((a.flurstueck :: text),'|', 3) 	AS auf_plot3,
        split_part((a.flurstueck :: text),'|', 4) 	AS auf_plot4,
        split_part((a.flurstueck :: text),'|', 5) 	AS auf_plot5,
        split_part((a.flurstueck :: text),'|', 6) 	AS auf_plot6,
        split_part((a.flurstueck :: text),'|', 7) 	AS auf_plot7,
        split_part((a.flurstueck :: text),'|', 8) 	AS auf_plot8,
        split_part((a.flurstueck :: text),'|', 9) 	AS auf_plot9
        --only two have entries with more than 9 plots, 
        --I can tell from the title that neither of them has to do with
        --rooftop additions or residential buildings, so I'm only including 
        --only the first 9 plots referred to in the aufstockung_permits table.
FROM 	gemarkungen AS g
JOIN	aufstockung_permits AS a
ON		g.name = a.gemarkung2
ORDER BY auf_plot7 DESC;

--These are the two entries in the aufstockung_permits table
--that have more than 9 plots:
SELECT filereference, title
FROM aufstockung_permits
WHERE "id" = '5148e855-0f43-493c-8fcf-9a8531b0c928'
OR "id" = '72e0a36f-fcc6-4b14-9ff2-707235aa63ff';

--Preparing the dataset for mapping: create the FSK 
--AIM: concatinate building plot and gemarkung codes to make an attribute
--that can be combined with geometry data for plots (separate shapefile).
--STEP 1: split plot data into one column
--The following splits the flurstueck column into an one column.
--This is what I will use to concatinate the flurstueck and gemarkung
--information into an "fsk" which can be used to join the aufstockung_permits
--table with the flurstuecke spatial dataset and map the results.
CREATE TABLE auf_permit_fsk AS
SELECT	a.id										AS auf_id,
		g.gemarkung_ 								AS gem_no,
        unnest(string_to_array((a.flurstueck :: text),'|')) AS plot
FROM 	gemarkungen AS g
JOIN	aufstockung_permits AS a
ON		g.name = a.gemarkung2;
--STEP 2: concatinate gemarkung and plot codes, adding "02", the code for Hamburg
--and underscores to create the ALKIS FSK.
--Update the table, adding column with FSK, concatinating columns "gem_no" and "plot"
ALTER TABLE auf_permit_fsk
ADD fsk varchar;
UPDATE auf_permit_fsk
SET fsk = '02'||gem_no||'___'||(LPAD(plot::text, 5, '0'))||'______';

DROP TABLE auf_permit_fsk; --in case I need to drop view.
SELECT * FROM auf_permit_fsk --look at view auf_permit_fsk, which I will use to create the fsk for mapping.
--NOW, I have everything I need to be able to plot this on a map!


--Create table of the relevant information to join with the flurstueck geometries to 
--map the resulting "aufstockung" plots. This inlcudes ALL plots for "auftstockung", 
--not only plots that have possible apartment buildings.
CREATE TABLE aufstockung_plots AS
SELECT 	a.auf_id 	AS permit_id,
		a.fsk		AS permit_fsk,
        f.geom		AS geom
FROM auf_permit_fsk AS a		
JOIN flurstuecke 	AS f
ON a.fsk = f.fsk;
--Add spatial index.
CREATE INDEX aufstockung_plots_geom_idx
	ON aufstockung_plots
    USING GIST(geom);


--Filter rooftop addtion data apartment buildings
--Preparation: Create GFA and area-to-perimeter ratio for buildings ("buildings" which 
--is which is based on ALKIS 2017-04-01 imported using the DB manager in QGIS)
--STEP1: identify apartment buildings, create "mfh" base layer.<--created from "buildings", 
--which is based on ALKIS 2017-04-01.
--STEP2: identify the plots on which mfh are located.
--STEP3: filter rooftop addtion permit data for only mfh plots.

--PREPARATION
--Calculating the above-ground GROSS FLOOR AREA (GFA; brutto geschossfläche, BGF) of all buildings in Hamburg.
--This simple way of calculating the GFA will overestimate the GFA for 
--almost all buildings.
--Because only the footprint of the building is available as an object in ALKIS, 
--buildings that have a larger ground floor and smaller
--upper stories will have a very overesitmated BGF. This might end up being problematic
--in my analysis, meaning that I will over estimate the existing built density.
--Other applications for BGF: connect to plots, and blocks to estimate GFZ.

--I've imported the buildings into postgresql through QGIS and named the table "building".
--To prepare all of the spatial data for entry into the databse it has to be saved as a shapefile,
--have the same reference system (SRID:25832), otherwise you can't do spatial joins
--with the other datasets.

--Dochev at al. 2017 (explanation of GEWISS assumptions when mapping, p. 11): 
--(1) GFA = building geometry * # of above-ground stories.
--(2) exclude buildings with a GFA less than 30m2 that are 
--listed as having a residential function, assume these are outbuildings.
--(3) exclude buildings with an area-to-perimeter ratio greater than 9.

--Create column in "building" with the above-ground GFA:
ALTER TABLE public.building
ADD gfa integer;
UPDATE public.building
SET gfa = (grundflaec * anzahldero); 
--here I can either use grundflaec or the function ST_Area(building.geom), 
--but the data aren't that precise anyway. Also, I don't know if there are some buildings
--for which grundflaec is purposefully blank.

SELECT * FROM building LIMIT 50; --take a look at the resulting table. Looks good.

--Create column in "building" with the area-to-perimeter ratio:
ALTER TABLE public.building
ADD areaperimeter numeric(10,2);
UPDATE public.building
SET areaperimeter = (ST_Area(building.geom) / ST_Perimeter(building.geom));

--Look at objects for which the area-to-perimeter ratio is greater than 9.
SELECT * FROM building
WHERE (areaperimeter > '9')
AND (bauweise > 0);
--Same selection in QGIS: ("areaperimeter" > 9) AND ("bauweise" IS NOT NULL).

--STEP1:
--Create new table with apartment buildings. Using selection criteria 
--adapted from Dochev at al. For buildings with a residential function and no 
--assigned bauweise, buildings with more than 2 stories are included, too.
CREATE TABLE public.mfh AS 
SELECT 	building.fid 		AS fid,
		building.geom 		AS geom,
		building.gebaeudefu AS use,
        building.bauweise 	AS bauweise,
        building.dachform 	AS roof, 
        building.grundflaec AS area,
        building.anzahldero AS story
FROM public.building
WHERE building.gebaeudefu :: varchar(20) LIKE '1%'
      AND ((building.bauweise = '1100' AND building.anzahldero >= 3)
          OR (building.bauweise = '2100' AND building.anzahldero >= 3) 
          OR building.bauweise = '1200'
          OR (building.bauweise = '2200' AND building.anzahldero >= 3) 
          OR building.bauweise = '2400' 
          OR building.bauweise = '2500' 
          OR (building.bauweise IS NULL AND building.anzahldero >= 3))
   	  AND building.areaperimeter < 9;

--Create spatial index for the table "mfh". This is necessary to reduce the time it takes
--to make a spatial join.
CREATE INDEX mfh_geom_idx
	ON mfh
    USING GIST(geom);

--STEP2:
--Identify the plots on which mfh are located and create new table "plots_mfh"
CREATE TABLE plots_mfh AS
SELECT
	f.fsk AS fsk,
    f.geom AS geom
FROM public.flurstuecke AS f
JOIN public.mfh AS b
ON ST_Contains(f.geom, ST_PointOnSurface(b.geom));
--Add spatial index.
CREATE INDEX plots_mfh_geom_idx
	ON plots_mfh
    USING GIST(geom);

--STEP3: Selection
--Only apartment building plots, only "aufstockung" = true
DROP TABLE plots_mfh_only_auf;
CREATE TABLE plots_mfh_only_auf AS 
SELECT DISTINCT
		a.permit_id				AS id_fsk,
        a.geom					AS geom,
        p.filereference			AS fileref,
        p.jahr					AS fileyear,
        p.title					AS title,
        p.aufstockung			AS aufstockung,
        p.vorbescheid			AS vorbescheid,
        p.permit_vereinfacht	AS vereinfach,
        p.permit_normal			AS normal_permit
FROM plots_mfh_all_auf	AS a		
JOIN aufstockung_permits 	AS p
ON a.permit_id = p.id
WHERE (p.aufstockung = 'true')
ORDER BY normal_permit, title, fileref;
--Create spatial index for table "plots_mfh_only_auf". This is necessary for later
--spatial joins.
CREATE INDEX plots_mfh_only_auf_geom_idx
	ON plots_mfh_only_auf
    USING GIST(geom);

--How many unique projects (filereferences) are there for rooftop additions on plots
--with apartment buildings? There are 259 distinct filereferences and 342 entries in the
--table total, since the projects cover multiple plots
SELECT * FROM plots_mfh_only_auf;

--Create a selection for mapping, of only the mfh buiildings
--that are on the plots with rooftop addition permits/vorbescheide.
--For this join I need tables: "mfh" and only_auf_plots_mfh.
SELECT count(*) FROM mfh; --just looking at data
SELECT * FROM plots_mfh_only_auf; --just looking at data
CREATE TABLE mfh_auf AS
SELECT DISTINCT --if only "select", then 447 entries. If "select distinct" then 368 entries.
	b.geom 		AS geom,
    b.fid 		AS fid,
    p.fileref	AS filereference
FROM mfh AS b
JOIN plots_mfh_only_auf AS p
ON ST_Intersects(p.geom,ST_PointOnSurface(b.geom));
--Create spatial index for mfh_auf
CREATE INDEX mfh_auf_geom_idx
	ON mfh_auf
    USING GIST(geom);

--Connecting the addresses from ALKIS to the properties referred to in the building permits.
--This step is really just to help me in the data-gathering process.
--The shapefile ALKIS_Adressen_HH_2016_03_24 is already loaded into the database via QGIS
--as table "address".
SELECT * FROM address LIMIT 200; --take a look at the attributes in the "address" table.
--The relevant columns are geom, strname, hausnr, zusatz, objectid, since I 
--need the street name and house number for entering the addresses in google, I
--need the geometry to be able to perform a spatial join with the rooftop addtion plots,
--and the objectid is included for good measure to have a unique id of each row in the
--dataset. Create new table with a selection of only the addresses that are within 
--the mfh buildings on rooftop addition plots.
CREATE TABLE address_auf AS
SELECT DISTINCT
	ad.geom 	AS geom,
    ad.objectid	AS objectid,
    ad.strname 	AS strname,
    ad.hausnr 	AS housenr,
    ad.zusatz 	AS zusatz
FROM public.mfh_auf AS b
JOIN public.address AS ad
ON ST_Intersects(b.geom, ST_PointOnSurface(ad.geom));
--Create spatial index for table "address_auf"
CREATE INDEX address_auf_geom_idx
	ON address_auf
    USING GIST(geom);  

--Now that I have the parts (various tables), I can join the columns from various tables
--together to make the final selection of projects for data collection.
SELECT * FROM aufstockung_plots;	-- (permit_id (file id), permit_fsk, geom)
SELECT * FROM plots_mfh_only_auf;	-- 	(id_fsk (file id), geom, fileref, fileyear, title,
									--	aufstockung (t/f), vorbescheid (t/f), vereinfach (t/f),
                                    --	normal_permit (t/f))


--MAKING THE FINAL TABLE TO COLLECT DATA
--I need:
	--fsk 				(plot number, first one that comes up)			FROM aufstockung_plots.permit_fsk
    --plot				(from original sheet, multiple plot no)			FROM aufstockung_permits.flurstueck
    --geom 				(plot geometry for the first one that comes up)	FROM plots_mfh_only_auf.geom
    --title																FROM plots_mfh_only_auf.title
    --address_full 		(one per filereference, concatinated) 			FROM address_auf [CONCAT(strname,' ', housenr,zusatz)]
    --**fileref			(LIMITING aspect, select distinct) 				FROM plots_mfh_only_auf.fileref
    --fileyear															FROM plots_mfh_only_auf.fileyear
    --id	 			(file id from JSON)								FROM plots_mfh_only_auf.id
    --publishingdate	(date the file was published online)			FROM baugenehmigungen
    --vorbescheid														FROM plots_mfh_only_auf.vorbescheid
    --vereinfach														FROM plots_mfh_only_auf.vereinfach
    --normal_permit														FROM plots_mfh_only_auf.normal_permit
    --aenderungsbescheid												FROM plots_mfh_only_auf.aenderungsbescheid
CREATE TABLE data_collection AS
SELECT DISTINCT ON (p.fileref)
 d.fsk,
 c.plots,
 p.geom,
 p.title,
 a.address_full,
 p.fileref,
 p.fileyear,
 p.id,
 b.publishingdate,
 p.vorbescheid,
 p.vereinfach,
 p.normal_permit,
 p.aenderungsbescheid
 FROM plots_mfh_only_auf AS p JOIN
 			(SELECT geom, CONCAT(strname,' ',housenr,zusatz) AS address_full
         	FROM address_auf) AS a ON ST_Contains(p.geom,a.geom)
 LEFT JOIN 	(SELECT filereference, flurstueck AS plots
      		FROM aufstockung_permits) AS c ON c.filereference = p.fileref
 LEFT JOIN 	(SELECT geom, permit_fsk AS fsk
            FROM aufstockung_plots) AS d ON d.geom = p.geom
 LEFT JOIN (SELECT publishingdate, id FROM public.baugenehmigungen) AS b
 			ON b.id = p.id
 ORDER BY p.fileref;
 
--Create spatial index for table "data_collection".
CREATE INDEX data_collection_geom_idx
	ON data_collection
    USING GIST(geom);
SELECT * FROM data_collection ORDER BY fileyear;
--Export table as csv for data entry
--example export to csv:
--COPY plots_mfh_only_auf TO '/Users/Shared/PostgreSQL_Data/plots_mfh_only_auf_TEST.csv' DELIMITER ',' CSV HEADER;
COPY data_collection TO '/Users/Shared/PostgreSQL_Data/data_collection_TEST.csv' DELIMITER ',' CSV HEADER;

--After data entry is complete, I need to re-upload the restulting table.
--I will also create a table with geometries for the confirmed buildings that are 
--referred to in the permit, this file will be based on the ALKIS-based "building" dataset
--(Using "mfh_auf" is not appropriate because some of the permit meta data was inaccurate with
--incorrect or missing plots that then caused some buildigs not to be selected; also because where
--there was only one entry row of metadata but multiple plots, only one plot would have been
--selected).
--I only include the buildings that are confirmed residential rooftop additions (Category 1),
--and confirmed proposed rooftop additions that have not yet been built (Category 2)
--Rooftop additions to other building types and non-relevant permits are not included in the 
--building-level analysis (Categories 3-5).


--Uploading the completed data collection table for ONLY Categories 1 and 2, -relevant data,
--not data referring to exemptions and permits. This is the table to understand the building-level
--characteristics of the existing building applicable for rooftop additions. Extra rows where 
--there were multiple unique file references for the same building are not included. 
DROP TABLE public.collected_1_2_b;
CREATE TABLE public.collected_1_2_b
(
    "id"             				varchar(20),
	relevance              			varchar(40),
    relevance_notes					varchar(100),
	project_no	     				varchar(20),
	stats_used_p       				boolean,
	building_no        				varchar(20),
	stats_used_b           			boolean,
	duplicate	      				boolean,
	fid_alkis_building     			varchar(40),
	file_no          				varchar(20),
	stats_used_f           			boolean,
	fileref		      				varchar(200),
	fileyear	      				varchar(40),
    "2014_and_later"	 			boolean,
    permit_type			 			varchar(200),
    address_full					varchar(200),
    date_visited					varchar(40),
    project_status					varchar(200),
    age_class						varchar(200),
    building_type_below				varchar(200),
    apartment_building_type			varchar(200),
    block_type						varchar(100),
    story_no_geb_vor_auf			real,--varchar(40),
    story_no_geb_nach_auf			real,--varchar(40),
    story_no_diff					real,--varchar(40),
    story_no_auf					real,--varchar(40),
    aufstockung_type				varchar(200),
    story_no_auf_proposed			real,--varchar(40),
    story_no_auf_approved			real,--varchar(40),
    story_no_geb_nach_auf_proposed	real,--varchar(40),
    story_no_geb_nach_auf_approved	real,--varchar(40),
    story_no_diff_proposed			real,--varchar(40),
    story_no_diff_approved			real,--varchar(40),
    approval_status					varchar(40),
    id2								varchar(100)
);

COPY public.collected_1_2_b FROM '/Users/Shared/PostgreSQL_Data/cat_1_2_Sep16_selecteddata_test.csv' WITH (DELIMITER ',', HEADER, FORMAT csv);

--Add spatial information for the buildings (attribute join)
--In addition to collected data on number of stories and age class,
--include from ALKIS: area of building footprint, Bauweise, number of stories, 
--Baujahr, area-perimeter ratio
DROP TABLE results_alkis_b 
CREATE TABLE results_alkis_b AS
SELECT
    a."id" AS id_collected,
    a.building_no,
    a.relevance,
    a.story_no_geb_vor_auf,
    a.story_no_auf,
    a.story_no_auf_approved,
    a.approval_status,
    a.age_class,
    b.fid,
    b.gebaeudefu,
    b.anzahldero,
    b.grundflaec,
    b.bauweise,
    b.baujahr1,
    b.areaperimeter,
    b.geom
 FROM public.collected_1_2_b AS a JOIN
  (SELECT fid, gebaeudefu, anzahldero, grundflaec,
   bauweise, baujahr1, areaperimeter, geom FROM building) AS b
   ON CAST(a.fid_alkis_building as numeric) = b.fid;

--Create spatial index for table "results_alkis_b".
CREATE INDEX results_alkis_b_geom_idx
	ON results_alkis_b
    USING GIST(geom);
