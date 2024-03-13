-- start_matchsubs
-- m/((Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (0[1-9]|[12][0-9]|3[01]) ([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](.[0-9]+)? (?!0000)[0-9]{4}.*)+(['"])/
-- s/((Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (0[1-9]|[12][0-9]|3[01]) ([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](.[0-9]+)? (?!0000)[0-9]{4}.*)+(['"])/xxx xx xx xx:xx:xx xxxx"/
-- end_matchsubs

/*--EXPLAIN_QUERY_BEGIN*/
create schema bfv_partition_plans;
set search_path=bfv_partition_plans;

--
-- Initial setup for all the partitioning test for this suite
--
-- start_ignore
CREATE LANGUAGE plpython3u;
-- end_ignore

create or replace function count_operator(query text, operator text) returns int as
$$
rv = plpy.execute('EXPLAIN ' + query)
search_text = operator
result = 0
for i in range(len(rv)):
    cur_line = rv[i]['QUERY PLAN']
    if search_text.lower() in cur_line.lower():
        result = result+1
return result
$$
language plpython3u;

create or replace function find_operator(query text, operator_name text) returns text as
$$
rv = plpy.execute('EXPLAIN ' + query)
search_text = operator_name
result = ['false']
for i in range(len(rv)):
    cur_line = rv[i]['QUERY PLAN']
    if search_text.lower() in cur_line.lower():
        result = ['true']
        break
return result
$$
language plpython3u;


-- Test UPDATE that moves row from one partition to another. The partitioning
-- key is also the distribution key in this case.
create table mpp3061 (i int) partition by range(i);
CREATE TABLE mpp3061_1 PARTITION of mpp3061 for values from (1) to (2);
CREATE TABLE mpp3061_2 PARTITION of mpp3061 for values from (2) to (3);
CREATE TABLE mpp3061_3 PARTITION of mpp3061 for values from (3) to (4);
CREATE TABLE mpp3061_4 PARTITION of mpp3061 for values from (4) to (5);

insert into mpp3061 values(1);
update mpp3061 set i = 2 where i = 1;
select tableoid::regclass, * from mpp3061 where i = 2;
drop table mpp3061;

--
-- Tests if it produces SIGSEGV from "select from partition_table group by rollup or cube function"
--

-- SETUP
create table mpp7980
(
 month_id date,
 bill_stmt_id  character varying(30),
 cust_type     character varying(10),
 subscription_status      character varying(30),
 voice_call_min           numeric(15,2),
 minute_per_call          numeric(15,2),
 subscription_id          character varying(15)
)
  PARTITION BY RANGE(month_id);

CREATE TABLE mpp7980_1 PARTITION of mpp7980 for values from ('2009-02-01') to ('2009-03-01');
CREATE TABLE mpp7980_2 PARTITION of mpp7980 for values from ('2009-03-01') to ('2009-04-01');
CREATE TABLE mpp7980_3 PARTITION of mpp7980 for values from ('2009-04-01') to ('2009-05-01');
CREATE TABLE mpp7980_4 PARTITION of mpp7980 for values from ('2009-05-01') to ('2009-06-01');
CREATE TABLE mpp7980_5 PARTITION of mpp7980 for values from ('2009-06-01') to ('2009-07-01');
CREATE TABLE mpp7980_6 PARTITION of mpp7980 for values from ('2009-07-01') to ('2009-08-01');

-- TEST
select count_operator('select cust_type, subscription_status,count(distinct subscription_id),sum(voice_call_min),sum(minute_per_call) from mpp7980 where month_id =E''2009-04-01'' group by rollup(1,2);','SIGSEGV');

insert into mpp7980 values('2009-04-01','xyz','zyz','1',1,1,'1');
insert into mpp7980 values('2009-04-01','zxyz','zyz','2',2,1,'1');
insert into mpp7980 values('2009-03-03','xyz','zyz','4',1,3,'1');
select cust_type, subscription_status,count(distinct subscription_id),sum(voice_call_min),sum(minute_per_call) from mpp7980 where month_id ='2009-04-01' group by rollup(1,2);

-- CLEANUP
drop table mpp7980;


-- ************ORCA ENABLED**********


--
-- MPP-23195
--

-- SETUP
-- start_ignore
set polar_px_optimizer_enable_bitmapscan=on;
set polar_px_optimizer_enable_indexjoin=on;
drop table if exists mpp23195_t1;
drop table if exists mpp23195_t2;
-- end_ignore

create table mpp23195_t1 (i int) partition by range(i);
CREATE TABLE mpp23195_t1_1 PARTITION of mpp23195_t1 for values from (1) to (10);
CREATE TABLE mpp23195_t1_2 PARTITION of mpp23195_t1 for values from (10) to (20);

create index index_mpp23195_t1_i on mpp23195_t1(i);
create table mpp23195_t2(i int);

insert into mpp23195_t1 values (generate_series(1,19));
insert into mpp23195_t2 values (1);

-- TEST
select find_operator('select * from mpp23195_t1,mpp23195_t2 where mpp23195_t1.i < mpp23195_t2.i;', 'Dynamic Index Scan');
select * from mpp23195_t1,mpp23195_t2 where mpp23195_t1.i < mpp23195_t2.i;

-- CLEANUP
-- start_ignore
drop table if exists mpp23195_t1;
drop table if exists mpp23195_t2;
set polar_px_optimizer_enable_bitmapscan=off;
set polar_px_optimizer_enable_indexjoin=off;
-- end_ignore


--
-- Check we have Dynamic Index Scan operator and check we have Nest loop operator
--

-- SETUP
-- start_ignore
drop table if exists mpp21834_t1;
drop table if exists mpp21834_t2;
-- end_ignore

create table mpp21834_t1 (i int, j int) partition by range(i);
CREATE TABLE mpp21834_t1_1 PARTITION of mpp21834_t1 for values from (1) to (10);
CREATE TABLE mpp21834_t1_2 PARTITION of mpp21834_t1 for values from (10) to (20);


create index index_1 on mpp21834_t1(i);

create index index_2 on mpp21834_t1(j);

create table mpp21834_t2(i int, j int);

-- TEST
set polar_px_optimizer_enable_hashjoin = off;
select find_operator('analyze select * from mpp21834_t2,mpp21834_t1 where mpp21834_t2.i < mpp21834_t1.i;','Dynamic Index Scan');
select find_operator('analyze select * from mpp21834_t2,mpp21834_t1 where mpp21834_t2.i < mpp21834_t1.i;','Nested Loop');

-- CLEANUP
drop index index_2;
drop index index_1;
drop table if exists mpp21834_t2;
drop table if exists mpp21834_t1;
reset polar_px_optimizer_enable_hashjoin;


--
-- A rescanning of DTS with its own partition selector (under sequence node)
--

-- SETUP
-- start_ignore
set polar_px_optimizer_enable_broadcast_nestloop_outer_child=on;
drop table if exists mpp23288;
-- end_ignore

create table mpp23288(a int, b int) 
  partition by range (a);
CREATE TABLE mpp23288_1 PARTITION of mpp23288 for values from (1) to (5);
CREATE TABLE mpp23288_2 PARTITION of mpp23288 for values from (5) to (10);
CREATE TABLE mpp23288_3 PARTITION of mpp23288 for values from (10) to (21);

insert into mpp23288(a) select generate_series(1,20);

analyze mpp23288;

-- TEST
select count_operator('select t2.a, t1.a from mpp23288 as t1 join mpp23288 as t2 on (t1.a < t2.a and t2.a =10) order by t2.a, t1.a;','Dynamic Seq Scan');
select t2.a, t1.a from mpp23288 as t1 join mpp23288 as t2 on (t1.a < t2.a and t2.a =10) order by t2.a, t1.a;

select count_operator('select t2.a, t1.a from mpp23288 as t1 join mpp23288 as t2 on (t1.a < t2.a and (t2.a = 10 or t2.a = 5 or t2.a = 12)) order by t2.a, t1.a;','Dynamic Seq Scan');
select t2.a, t1.a from mpp23288 as t1 join mpp23288 as t2 on (t1.a < t2.a and (t2.a = 10 or t2.a = 5 or t2.a = 12)) order by t2.a, t1.a;

select count_operator('select t2.a, t1.a from mpp23288 as t1 join mpp23288 as t2 on t1.a < t2.a and t2.a = 1 or t2.a < 10 order by t2.a, t1.a;','Dynamic Seq Scan');
select t2.a, t1.a from mpp23288 as t1 join mpp23288 as t2 on t1.a < t2.a and t2.a = 1 or t2.a < 10 order by t2.a, t1.a;

-- CLEANUP
-- start_ignore
drop table if exists mpp23288;
set polar_px_optimizer_enable_broadcast_nestloop_outer_child=off;
-- end_ignore


--
-- Tests if DynamicIndexScan sets tuple descriptor of the planstate->ps_ResultTupleSlot
--

-- SETUP
-- start_ignore
drop table if exists mpp24151_t;
drop table if exists mpp24151_pt;
-- end_ignore

create table mpp24151_t(dist int, tid int, t1 text, t2 text);
create table mpp24151_pt(dist int, pt1 text, pt2 text, pt3 text, ptid int) 
PARTITION BY RANGE(ptid); 
CREATE TABLE mpp24151_pt_1 PARTITION of mpp24151_pt for values from (0) to (1);
CREATE TABLE mpp24151_pt_2 PARTITION of mpp24151_pt for values from (1) to (2);
CREATE TABLE mpp24151_pt_3 PARTITION of mpp24151_pt for values from (2) to (3);
CREATE TABLE mpp24151_pt_4 PARTITION of mpp24151_pt for values from (3) to (4);
CREATE TABLE mpp24151_pt_5 PARTITION of mpp24151_pt for values from (4) to (5);
CREATE TABLE mpp24151_pt_6 PARTITION of mpp24151_pt default;

create index mpp24151_pt1_idx on mpp24151_pt using btree (pt1);
create index mpp24151_ptid_idx on mpp24151_pt using btree (ptid);
insert into mpp24151_pt select i, 'hello' || 0, 'world', 'drop this', i % 6 from generate_series(0,100)i;
insert into mpp24151_pt select i, 'hello' || i, 'world', 'drop this', i % 6 from generate_series(0,200000)i;

insert into mpp24151_t select i, i % 6, 'hello' || i, 'bar' from generate_series(0,10)i;
analyze mpp24151_pt;
analyze mpp24151_t;

-- TEST
set polar_px_optimizer_enable_dynamictablescan = off;

-- GPDB_12_MERGE_FIXME: With the big refactoring t how Partition Selectors are
-- implemented during the v12 merge, I'm not sure if this test is testing anything
-- useful anymore. And/or it redundant with the tests in 'dpe'?
select count_operator('select * from mpp24151_t, mpp24151_pt where tid = ptid and pt1 = E''hello0'';','->  Partition Selector');
select * from mpp24151_t, mpp24151_pt where tid = ptid and pt1 = 'hello0'
order by tid, mpp24151_t.dist, mpp24151_pt.dist;

-- CLEANUP
drop index mpp24151_pt1_idx;
drop index mpp24151_ptid_idx;
drop table if exists mpp24151_t;
drop table if exists mpp24151_pt;
reset polar_px_optimizer_enable_dynamictablescan;


--
-- No DPE (Dynamic Partition Elimination) on second child of a union under a join
--

-- SETUP
-- start_ignore
drop table if exists t;
drop table if exists p1;
drop table if exists p2;
drop table if exists p3;
drop table if exists p;
-- end_ignore

create table p1 (a int, b int) partition by range(b);
CREATE TABLE p1_1 PARTITION of p1 for values from (1) to (21);
CREATE TABLE p1_2 PARTITION of p1 for values from (21) to (41);
CREATE TABLE p1_3 PARTITION of p1 for values from (41) to (61);
CREATE TABLE p1_4 PARTITION of p1 for values from (61) to (81);
CREATE TABLE p1_5 PARTITION of p1 for values from (81) to (101);

create table p2 (a int, b int) partition by range(b);
CREATE TABLE p2_1 PARTITION of p2 for values from (1) to (21);
CREATE TABLE p2_2 PARTITION of p2 for values from (21) to (41);
CREATE TABLE p2_3 PARTITION of p2 for values from (41) to (61);
CREATE TABLE p2_4 PARTITION of p2 for values from (61) to (81);
CREATE TABLE p2_5 PARTITION of p2 for values from (81) to (101);

create table p3 (a int, b int) partition by range(b);
CREATE TABLE p3_1 PARTITION of p3 for values from (1) to (21);
CREATE TABLE p3_2 PARTITION of p3 for values from (21) to (41);
CREATE TABLE p3_3 PARTITION of p3 for values from (41) to (61);
CREATE TABLE p3_4 PARTITION of p3 for values from (61) to (81);
CREATE TABLE p3_5 PARTITION of p3 for values from (81) to (101);

create table p (a int, b int);
create table t(a int, b int);

insert into t select g, g*10 from generate_series(1,100) g;

insert into p1 select g, g%99 +1 from generate_series(1,10000) g;

insert into p2 select g, g%99 +1 from generate_series(1,10000) g;

insert into p3 select g, g%99 +1 from generate_series(1,10000) g;

insert into p select g, g%99 +1 from generate_series(1,10000) g;

analyze t;
analyze p1;
analyze p2;
analyze p3;
analyze p;

-- TEST
select count_operator('select * from (select * from p1 union all select * from p2) as p_all, t where p_all.b=t.b;','Partition Selector');

select count_operator('select * from (select * from p1 union select * from p2) as p_all, t where p_all.b=t.b;','Partition Selector');

select count_operator('select * from (select * from p1 except all select * from p2) as p_all, t where p_all.b=t.b;','Partition Selector');

select count_operator('select * from (select * from p1 except select * from p2) as p_all, t where p_all.b=t.b;','Partition Selector');

select count_operator('select * from (select * from p1 intersect all select * from p2) as p_all, t where p_all.b=t.b;','Partition Selector');

select count_operator('select * from (select * from p1 union select * from p2 union all select * from p3) as p_all, t where p_all.b=t.b;','Partition Selector');

select count_operator('select * from (select * from p1 union select * from p2 union all select * from p) as p_all, t where p_all.b=t.b;','Partition Selector');

select count_operator('select * from (select * from p1 union select * from p union all select * from p2) as p_all, t where p_all.b=t.b;','Partition Selector');

select count_operator('select * from (select * from p1 union select * from p2 intersect all select * from p3) as p_all, t where p_all.b=t.b;','Partition Selector');

select count_operator('select * from (select * from p1 union select * from p intersect all select * from p2) as p_all, t where p_all.b=t.b;','Partition Selector');

-- CLEANUP
-- start_ignore
drop table t;
drop table p1;
drop table p2;
drop table p3;
drop table p;
-- end_ignore


--
-- Gracefully handle NULL partition set from BitmapTableScan, DynamicTableScan and DynamicIndexScan
--

-- SETUP
-- start_ignore
drop table if exists dts;
drop table if exists dis;
drop table if exists dbs;
-- end_ignore

create table dts(c1 int, c2 int) partition by range(c2);
CREATE TABLE dts_1 PARTITION of dts for values from (1) to (2);
CREATE TABLE dts_2 PARTITION of dts for values from (2) to (3);
CREATE TABLE dts_3 PARTITION of dts for values from (3) to (4);
CREATE TABLE dts_4 PARTITION of dts for values from (4) to (5);
CREATE TABLE dts_5 PARTITION of dts for values from (5) to (6);
CREATE TABLE dts_6 PARTITION of dts for values from (6) to (7);
CREATE TABLE dts_7 PARTITION of dts for values from (7) to (8);
CREATE TABLE dts_8 PARTITION of dts for values from (8) to (9);
CREATE TABLE dts_9 PARTITION of dts for values from (9) to (10);
CREATE TABLE dts_10 PARTITION of dts for values from (10) to (11);

create table dis(c1 int, c2 int, c3 int) partition by range(c2);
CREATE TABLE dis_1 PARTITION of dis for values from (1) to (2);
CREATE TABLE dis_2 PARTITION of dis for values from (2) to (3);
CREATE TABLE dis_3 PARTITION of dis for values from (3) to (4);
CREATE TABLE dis_4 PARTITION of dis for values from (4) to (5);
CREATE TABLE dis_5 PARTITION of dis for values from (5) to (6);
CREATE TABLE dis_6 PARTITION of dis for values from (6) to (7);
CREATE TABLE dis_7 PARTITION of dis for values from (7) to (8);
CREATE TABLE dis_8 PARTITION of dis for values from (8) to (9);
CREATE TABLE dis_9 PARTITION of dis for values from (9) to (10);
CREATE TABLE dis_10 PARTITION of dis for values from (10) to (11);

create index dis_index on dis(c3);
CREATE TABLE dbs(c1 int, c2 int, c3 int) partition by range(c2);
CREATE TABLE dbs_1 PARTITION of dbs for values from (1) to (2);
CREATE TABLE dbs_2 PARTITION of dbs for values from (2) to (3);
CREATE TABLE dbs_3 PARTITION of dbs for values from (3) to (4);
CREATE TABLE dbs_4 PARTITION of dbs for values from (4) to (5);
CREATE TABLE dbs_5 PARTITION of dbs for values from (5) to (6);
CREATE TABLE dbs_6 PARTITION of dbs for values from (6) to (7);
CREATE TABLE dbs_7 PARTITION of dbs for values from (7) to (8);
CREATE TABLE dbs_8 PARTITION of dbs for values from (8) to (9);
CREATE TABLE dbs_9 PARTITION of dbs for values from (9) to (10);
CREATE TABLE dbs_10 PARTITION of dbs for values from (10) to (11);
create index dbs_index on dbs using bitmap(c3);


-- TEST
select find_operator('(select * from dts where c2 = 1) union (select * from dts where c2 = 2) union (select * from dts where c2 = 3) union (select * from dts where c2 = 4) union (select * from dts where c2 = 5) union (select * from dts where c2 = 6) union (select * from dts where c2 = 7) union (select * from dts where c2 = 8) union (select * from dts where c2 = 9) union (select * from dts where c2 = 10);', 'Dynamic Seq Scan');

(select * from dts where c2 = 1) union
(select * from dts where c2 = 2) union
(select * from dts where c2 = 3) union
(select * from dts where c2 = 4) union
(select * from dts where c2 = 5) union
(select * from dts where c2 = 6) union
(select * from dts where c2 = 7) union
(select * from dts where c2 = 8) union
(select * from dts where c2 = 9) union
(select * from dts where c2 = 10);

set polar_px_optimizer_enable_dynamictablescan = off;
select find_operator('(select * from dis where c3 = 1) union (select * from dis where c3 = 2) union (select * from dis where c3 = 3) union (select * from dis where c3 = 4) union (select * from dis where c3 = 5) union (select * from dis where c3 = 6) union (select * from dis where c3 = 7) union (select * from dis where c3 = 8) union (select * from dis where c3 = 9) union (select * from dis where c3 = 10);', 'Dynamic Index Scan');

(select * from dis where c3 = 1) union
(select * from dis where c3 = 2) union
(select * from dis where c3 = 3) union
(select * from dis where c3 = 4) union
(select * from dis where c3 = 5) union
(select * from dis where c3 = 6) union
(select * from dis where c3 = 7) union
(select * from dis where c3 = 8) union
(select * from dis where c3 = 9) union
(select * from dis where c3 = 10);

select find_operator('select * from dbs where c2= 15 and c3 = 5;', 'Bitmap Heap Scan');

select * from dbs where c2= 15 and c3 = 5;

-- CLEANUP
drop index dbs_index;
drop table if exists dbs;
drop index dis_index;
drop table if exists dis;
drop table if exists dts;
reset polar_px_optimizer_enable_dynamictablescan;

--
-- Partition elimination for heterogenous DynamicIndexScans
--

-- SETUP
-- start_ignore
drop table if exists pp;
drop index if exists pp_1_prt_1_idx;
drop index if exists pp_rest_1_idx;
drop index if exists pp_rest_2_idx;
set polar_px_optimizer_segments=2;
set polar_px_optimizer_partition_selection_log=on;
-- end_ignore
create table pp(a int, b int, c int) partition by range(b);
CREATE TABLE pp_1_prt_1 PARTITION of pp for values from (1) to (5);
CREATE TABLE pp_1_prt_2 PARTITION of pp for values from (5) to (10);
CREATE TABLE pp_1_prt_3 PARTITION of pp for values from (10) to (15);


insert into pp values (1,1,2),(2,6,2), (3,11,2);
-- Heterogeneous Index on the partition table
create index pp_1_prt_1_idx on pp_1_prt_1(c);
-- Create other indexes so that we can automate the repro for MPP-21069 by disabling tablescan
create index pp_rest_1_idx on pp_1_prt_2(c,a);
create index pp_rest_2_idx on pp_1_prt_3(c,a);
-- TEST
set polar_px_optimizer_enable_dynamictablescan = off;
select * from pp where b=2 and c=2;
select count_operator('select * from pp where b=2 and c=2;','Partition Selector');

-- CLEANUP
-- start_ignore
drop index if exists pp_rest_2_idx;
drop index if exists pp_rest_1_idx;
drop index if exists pp_1_prt_1_idx;
drop table if exists pp;
reset polar_px_optimizer_enable_dynamictablescan;
reset polar_px_optimizer_segments;
set polar_px_optimizer_partition_selection_log=off;
-- end_ignore


--
-- Partition elimination with implicit CAST on the partitioning key
--

-- SETUP
-- start_ignore
set polar_px_optimizer_segments=2;
set polar_px_optimizer_partition_selection_log=on;
DROP TABLE IF EXISTS ds_4;
-- end_ignore

CREATE TABLE ds_4
(
  month_id character varying(6),
  cust_group_acc numeric(10),
  mobile_no character varying(10)
)
PARTITION BY LIST(month_id);
CREATE TABLE ds_4_1 PARTITION OF ds_4 FOR VALUES IN ('200800');
CREATE TABLE ds_4_2 PARTITION OF ds_4 FOR VALUES IN ('200801');
CREATE TABLE ds_4_3 PARTITION OF ds_4 FOR VALUES IN ('200802');
CREATE TABLE ds_4_4 PARTITION OF ds_4 FOR VALUES IN ('200803');

-- TEST
select * from ds_4 where month_id = '200800';
select count_operator('select * from ds_4 where month_id = E''200800'';','Partition Selector');

select * from ds_4 where month_id > '200800';
select count_operator('select * from ds_4 where month_id > E''200800'';','Partition Selector');

select * from ds_4 where month_id <= '200800';
select count_operator('select * from ds_4 where month_id <= E''200800'';','Partition Selector');

select * from ds_4 a1,ds_4 a2 where a1.month_id = a2.month_id and a1.month_id > '200800';
select count_operator('select * from ds_4 a1,ds_4 a2 where a1.month_id = a2.month_id and a1.month_id > E''200800'';','Partition Selector');

-- CLEANUP
-- start_ignore
DROP TABLE IF EXISTS ds_4;
set polar_px_optimizer_partition_selection_log=off;
reset polar_px_optimizer_segments;

-- end_ignore

--
-- Test a hash agg that has a Sequence + Partition Selector below it.
--

-- SETUP
-- start_ignore
DROP TABLE IF EXISTS bar;
-- end_ignore
CREATE TABLE bar (b int, c int)
PARTITION BY RANGE (b);
CREATE TABLE bar_1 PARTITION of bar for values from (0) to (10);
CREATE TABLE bar_2 PARTITION of bar for values from (10) to (20);

INSERT INTO bar SELECT g % 20, g % 20 from generate_series(1, 1000) g;
ANALYZE bar;

SELECT b FROM bar GROUP BY b;

explain (costs off) select b FROM bar GROUP BY b;


-- CLEANUP
DROP TABLE IF EXISTS foo;
DROP TABLE IF EXISTS bar;




-- Partitioned tables with default partitions and indexes on all parts,
-- queries on them with a predicate on index column must not consider the scan
-- as partial and should not fallback.
CREATE TABLE part_tbl
(
	time_client_key numeric(16,0) NOT NULL,
	ngin_service_key numeric NOT NULL,
	profile_key numeric NOT NULL
)
PARTITION BY RANGE(time_client_key);
CREATE TABLE part_tbl_1 PARTITION of part_tbl for values from (2015111000) to (2015111100);
INSERT INTO part_tbl VALUES (2015111000, 479534741, 99999999);
INSERT INTO part_tbl VALUES (2015111000, 479534742, 99999999);
CREATE INDEX part_tbl_idx 
ON part_tbl(profile_key);
-- start_ignore
analyze part_tbl;
-- end_ignore
explain (costs off) select * FROM part_tbl WHERE profile_key = 99999999;
SELECT * FROM part_tbl WHERE profile_key = 99999999;
DROP TABLE part_tbl;

--
-- Test partition elimination, MPP-7891
--

-- cleanup
-- start_ignore
drop table if exists r_part;
drop table if exists r_co;

deallocate f1;
deallocate f2;
deallocate f3;
-- end_ignore

create table r_part(a int, b int) partition by range(a);
CREATE TABLE r_part_1 PARTITION of r_part for values from (1) to (2);
CREATE TABLE r_part_2 PARTITION of r_part for values from (2) to (3);
CREATE TABLE r_part_3 PARTITION of r_part for values from (3) to (4);
CREATE TABLE r_part_4 PARTITION of r_part for values from (4) to (5);
CREATE TABLE r_part_5 PARTITION of r_part for values from (5) to (6);
CREATE TABLE r_part_6 PARTITION of r_part for values from (6) to (7);
CREATE TABLE r_part_7 PARTITION of r_part for values from (7) to (8);
CREATE TABLE r_part_8 PARTITION of r_part for values from (8) to (9);
CREATE TABLE r_part_9 PARTITION of r_part for values from (9) to (10);

insert into r_part values (1,1), (2,2), (3,3), (4,4), (5,5), (6,6), (7,7), (8,8);

-- following tests rely on the data distribution, verify them
select * from r_part order by a,b;

analyze r_part;

explain (costs off) select * from r_part r1, r_part r2 where r1.a=1; -- should eliminate partitions in the r1 copy of r_part

-- the numbers in the filter should be both on segment 0
explain (costs off) select * from r_part where a in (7,8); -- should eliminate partitions

-- Test partition elimination in prepared statements
prepare f1(int) as select * from r_part where a = 1 order by a,b; 
prepare f2(int) as select * from r_part where a = $1 order by a,b;

execute f1(1); 
execute f2(1); 
execute f2(2); 


explain (costs off) select * from r_part where a = 1 order by a,b; -- should eliminate partitions
--force_explain
explain execute f1(1); -- should eliminate partitions 
--force_explain
explain execute f2(2); -- should eliminate partitions


-- test partition elimination in prepared statements on CO tables

--force_explain
explain execute f3(2); -- should eliminate partitions

-- start_ignore
drop table r_part;
drop table r_co;
deallocate f1;
deallocate f2;
deallocate f3;
-- end_ignore

--
-- Test partition elimination, MPP-7891
--

-- start_ignore
drop table if exists fact;
deallocate f1;

create table fact(x int, dd date, dt text) 
partition by range (dd);
CREATE TABLE fact_1 PARTITION of fact for values from ('2008-01-01') to ('2108-01-01');
CREATE TABLE fact_2 PARTITION of fact for values from ('2108-01-01') to ('2208-01-01');
CREATE TABLE fact_3 PARTITION of fact for values from ('2208-01-01') to ('2308-01-01');
CREATE TABLE fact_4 PARTITION of fact for values from ('2308-01-01') to ('2320-01-01');
-- end_ignore

analyze fact;

select '2009-01-02'::date = to_date('2009-01-02','YYYY-MM-DD'); -- ensure that both are in fact equal

explain (costs off) select * from fact where dd < '2009-01-02'::date; -- partitions eliminated

explain (costs off) select * from fact where dd < to_date('2009-01-02','YYYY-MM-DD'); -- partitions eliminated

explain (costs off) select * from fact where dd < current_date; --partitions eliminated

-- Test partition elimination in prepared statements

prepare f1(date) as select * from fact where dd < $1;

-- force_explain
explain execute f1('2009-01-02'::date); -- should eliminate partitions
-- force_explain
explain execute f1(to_date('2009-01-02', 'YYYY-MM-DD')); -- should eliminate partitions

-- start_ignore
drop table fact;
deallocate f1;
-- end_ignore

-- MPP-6247
-- Delete Using on partitioned table causes repetitive scans on using table	
create table mpp6247_foo ( c1 int, dt date ) 
 partition by range (dt);
CREATE TABLE mpp6247_foo_1 PARTITION of mpp6247_foo for values from ('2009-05-01') to ('2009-05-02');
CREATE TABLE mpp6247_foo_2 PARTITION of mpp6247_foo for values from ('2009-05-02') to ('2009-05-03');
CREATE TABLE mpp6247_foo_3 PARTITION of mpp6247_foo for values from ('2009-05-03') to ('2009-05-04');
CREATE TABLE mpp6247_foo_4 PARTITION of mpp6247_foo for values from ('2009-05-04') to ('2009-05-05');
CREATE TABLE mpp6247_foo_5 PARTITION of mpp6247_foo for values from ('2009-05-05') to ('2009-05-06');
CREATE TABLE mpp6247_foo_6 PARTITION of mpp6247_foo for values from ('2009-05-06') to ('2009-05-07');
CREATE TABLE mpp6247_foo_7 PARTITION of mpp6247_foo for values from ('2009-05-07') to ('2009-05-08');
CREATE TABLE mpp6247_foo_8 PARTITION of mpp6247_foo for values from ('2009-05-08') to ('2009-05-09');
CREATE TABLE mpp6247_foo_9 PARTITION of mpp6247_foo for values from ('2009-05-09') to ('2009-05-10');
CREATE TABLE mpp6247_foo_10 PARTITION of mpp6247_foo for values from ('2009-05-10') to ('2009-05-11');

create table mpp6247_bar (like mpp6247_foo);

-- EXPECT: Single HJ after partition elimination instead of sequence of HJ under Append
select count_operator('delete from mpp6247_foo using mpp6247_bar where mpp6247_foo.c1 = mpp6247_bar.c1 and mpp6247_foo.dt = ''2009-05-03''', 'Hash Join');

drop table mpp6247_bar;
drop table mpp6247_foo;

-- CLEANUP
-- start_ignore
set client_min_messages='warning';
drop schema if exists bfv_partition_plans cascade;
-- end_ignore
