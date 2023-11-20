-- config
/*--POLAR_ENABLE_PX*/
set client_min_messages to error;
set polar_enable_px = 1;
set polar_px_enable_insert_select = 1;
set polar_px_optimizer_enable_dml_constraints = 1;
set polar_px_enable_insert_order_sensitive = 0;

create function dml_explain_filter(text) returns setof text
language plpgsql as
$$
declare
    ln text;
begin
    for ln in execute $1
    loop
        -- Replace any actual rows with just 'N'
        ln := regexp_replace(ln, 'actual rows=\d+\M', 'actual rows=N', 'g');
        -- In sort output, the above won't match units-suffixed numbers
        ln := regexp_replace(ln, '\m\d+kB', 'NkB', 'g');
        return next ln;
    end loop;
end;
$$;

-- create table
\i sql/polar-px-dev/px_parallel_dml_init.sql

/*--EXPLAIN_QUERY_BEGIN*/
-- Slow SQL, Only once
-- Delete
EXPLAIN (VERBOSE, COSTS OFF) delete from px_parallel_dml_t2 as px_parallel_dml_t0 where px_parallel_dml_t0.c1 < (select c2 from px_parallel_dml_t1 order by c2 LIMIT 1);
delete from px_parallel_dml_t2 as px_parallel_dml_t0 where px_parallel_dml_t0.c1 < (select c2 from px_parallel_dml_t1 order by c2 LIMIT 1);
EXPLAIN (VERBOSE, COSTS OFF) delete from px_parallel_dml_t1 as px_parallel_dml_t0 where px_parallel_dml_t0.c1 < (select c2 from px_parallel_dml_t2 order by c2 LIMIT 1);
delete from px_parallel_dml_t1 as px_parallel_dml_t0 where px_parallel_dml_t0.c1 < (select c2 from px_parallel_dml_t2 order by c2 LIMIT 1);
select count(*) from px_parallel_dml_t1;
select count(*) from px_parallel_dml_t2;

-- Update
EXPLAIN (VERBOSE, COSTS OFF) update px_parallel_dml_t2 set c1 = px_parallel_dml_t1.c2 from px_parallel_dml_t1;
update px_parallel_dml_t2 set c1 = px_parallel_dml_t1.c2 from px_parallel_dml_t1;
EXPLAIN (VERBOSE, COSTS OFF) update px_parallel_dml_t1 set c1 = px_parallel_dml_t2.c2 from px_parallel_dml_t2;
update px_parallel_dml_t1 set c1 = px_parallel_dml_t2.c2 from px_parallel_dml_t2;
select count(*) from px_parallel_dml_t1;
select count(*) from px_parallel_dml_t2;
EXPLAIN (VERBOSE, COSTS OFF) update px_parallel_dml_t2 set c2 = px_parallel_dml_t1.c2 from px_parallel_dml_t1;
update px_parallel_dml_t2 set c2 = px_parallel_dml_t1.c2 from px_parallel_dml_t1;
EXPLAIN (VERBOSE, COSTS OFF) update px_parallel_dml_t1 set c2 = px_parallel_dml_t2.c2 from px_parallel_dml_t2;
update px_parallel_dml_t1 set c2 = px_parallel_dml_t2.c2 from px_parallel_dml_t2;
select count(*) from px_parallel_dml_t1;
select count(*) from px_parallel_dml_t2;


-- One Writer worker
set polar_px_insert_dop_num = 1;
\i sql/polar-px-dev/px_parallel_dml_init.sql
\i sql/polar-px-dev/px_parallel_dml_base.sql

-- Writer workers < Reader workers
set polar_px_insert_dop_num = 3;
\i sql/polar-px-dev/px_parallel_dml_init.sql
\i sql/polar-px-dev/px_parallel_dml_base.sql

-- Writer workers == Read workers
set polar_px_insert_dop_num = 6;
\i sql/polar-px-dev/px_parallel_dml_init.sql
\i sql/polar-px-dev/px_parallel_dml_base.sql

-- Writer workers > Read workers
set polar_px_insert_dop_num = 10;
\i sql/polar-px-dev/px_parallel_dml_init.sql
\i sql/polar-px-dev/px_parallel_dml_base.sql

reset client_min_messages;