create database ecommerce_data;
use ecommerce_data;
select * from list_of_orders;
select * from order_details;
select * from sales_target;

-- Change column name
alter table list_of_orders
change column `Order ID` order_id varchar(255),
change column `Order Date` order_date varchar(50),
change column `CustomerName` customer_name varchar(255),
change column `State` state varchar(255),
change column `City` city varchar(255);

update list_of_orders
set order_date = str_to_date(order_date, '%Y-%m-%d')
where order_date <> '';

select min(order_date) as start_date,
max(order_date) as end_date,
count(distinct customer_name) as unique_customers,
count(distinct state) as states,
count(distinct city) as citis
from list_of_orders;

SELECT order_year, order_month, COUNT(*) AS total_orders
FROM list_of_orders
GROUP BY order_year, order_month
ORDER BY order_year, order_month;

SELECT state, COUNT(*) AS total_orders
FROM list_of_orders
GROUP BY state
ORDER BY total_orders DESC
LIMIT 10;

SELECT customer_name, COUNT(*) AS order_count
FROM list_of_orders
GROUP BY customer_name
ORDER BY order_count DESC
LIMIT 10;





update list_of_orders
set order_date = trim(order_date);

update list_of_orders
set order_date = null
where order_date = '' or order_date is null;

alter table list_of_orders
modify column order_date date; 

delete from list_of_orders
where order_date is null;

alter table list_of_orders
add column order_year int;

alter table list_of_orders
add column order_month int;

update list_of_orders
set order_year = year(order_date),
order_month = month(order_date);

select order_id, count(*) as cnt
from list_of_orders
group by order_id
having cnt > 1;



-- for order details

alter table order_details
change column `Order ID` order_id varchar(255),
change column `Amount` amount double,
change column `Profit` profit double,
change column `Quantity` quantity int,
change column `Category` category varchar(255),
change column `Sub-Category` sub_category varchar(255);


alter table sales_target
change column `Month of Order Date` order_month varchar(255),
change column `Category` category varchar(255),
change column `Target` target double;

UPDATE sales_target
SET order_month = STR_TO_DATE(CONCAT('01-', `order_month`), '%d-%b-%y');

select date_format(order_month, '%b-%Y') as order_date
from sales_target;

alter table sales_target
modify column  `order_month` date;

alter table sales_target
change column order_month order_date date;

-- 1) Data-quality checks
-- Any duplicate order_id?
select order_id, count(*) as cnt
from list_of_orders
group by order_id
having count(*) > 1;

-- Orphan details (detail rows whose header is missing)
select order_id, count(*) as detail_rows
from order_details d
left join list_of_orders o using(order_id)
where o.order_id is null
group by order_id;

-- Negative amounts / profits
-- profit less than -revenue is suspicious
select *
from order_details
where amount < 0 or profit < -amount;

-- Zero-quantity lines
select *
from order_details
where quantity <= 0;

-- Categories that exist in sales but never in targets (or vice-versa)

-- In sales but not in targets
select 'in_sales_only' as where_, category
from order_details
where category not in (select category from sales_target)
union all
-- In target but not in sales
select 'in_target_only', category
from sales_target
where category not in (select category from order_details);

-- 2) Core business KPIs
-- (a) Total Revenue, Profit, Orders, AOV

with sales as (
select d.order_id,
sum(d.amount) as revenue,
sum(d.profit) as profit,
sum(d.quantity) as units
from order_details d
group by d.order_id
)
select
count(*) as orders,
sum(revenue) as revenue,
sum(profit) as profit,
sum(units) as units,
round(sum(revenue) / nullif(count(*), 0), 2) as avg_order_value
from sales;

-- (b) Monthly trend (for line chart)
select date_format(o.order_date, '%Y-%m-01') as month_start,
sum(d.amount) as revenue,
sum(d.profit) as profit,
sum(d.quantity) as units
from list_of_orders o
join order_details d using (order_id)
group by month_start
order by month_start;

-- (c) Category mix (for stacked bar / donut)
select d.category,
sum(d.amount) as revenue,
sum(d.profit) as profit,
sum(d.quantity) as units
from order_details d
group by d.category
order by revenue desc;

-- (d) Sub-category top 10 by revenue (Pareto)
select d.category, d.sub_category,
sum(d.amount) as revenue
from order_details d
group by d.category, d.sub_category
order by revenue desc
limit 10;

-- 3) Customer & geography insights
-- (a) Unique customers, repeat rate
-- -- First month a customer bought and repeat customers

with c as (
select customer_name,
date_format(min(order_date), 'Y%-%m-01') as first_month,
count(distinct order_id) as orders_per_customer
from list_of_orders
group by customer_name
)
select
count(*) as customers,
sum(orders_per_customer >= 2) as repeat_customers,
round(100.0 * avg(orders_per_customer >= 2), 1) as repeat_rate_pct
from c;

-- (b) City leaderboard
select o.state, o.city,
count(distinct o.order_id) as orders,
sum(d.amount) as revenue,
sum(d.profit) as profit
from list_of_orders o
join order_details d using (order_id)
group by o.state, o.city
order by revenue desc
limit 10;

-- (c) Profitability heatmap (State × Category)
select o.state, d.category,
sum(d.amount) as revenue,
sum(d.profit) as profit,
round(100 * sum(d.profit)/nullif(sum(d.amount),0), 2) as margin_pct
from list_of_orders o
join order_details d using (order_id)
group by o.state, d.category
order by o.state, d.category;

-- 4) Basket & product analytics
-- (a) Average basket size (units per order)
with by_order as (
select order_id, sum(quantity) as units
from order_details
group by order_id
)
select round(avg(units), 2) as avg_units_per_order
from by_order;

-- (b) Cross-sell starting point (top sub-category pairs in same order)
with lines as (
    select order_id, sub_category
    from order_details
    group by order_id, sub_category
),
pairs as (
    select l1.sub_category as sub_a, l2.sub_category as sub_b
    from lines l1
    join lines l2
    on l1.order_id = l2.order_id
    and l1.sub_category < l2.sub_category
)
select sub_a, sub_b, count(*) as together_orders
from pairs
group by sub_a, sub_b
order by together_orders desc
limit 15;

-- 5) Target vs Actuals (perfect for a monthly scorecard)
-- (a) Prepare monthly actuals by category
with monthly_actuals as (
select date_format(o.order_date, '%Y-%m-01') as month_start,
d.category,
sum(d.amount) as revenue
from list_of_orders o
join order_details d using (order_id)
group by month_start, d.category
)
select m.month_start, m.category, m.revenue
from monthly_actuals m
order by m.month_start, m.category;

-- (b) Join to targets for Attainment% & Variance
WITH monthly_actuals AS (
  SELECT DATE_FORMAT(o.order_date, '%Y-%m-01') AS month_start,
         d.category,
         SUM(d.amount) AS revenue
  FROM list_of_orders o
  JOIN order_details d USING (order_id)
  GROUP BY month_start, d.category
)
SELECT
    t.order_date       AS month_start,
    t.category,
    COALESCE(a.revenue, 0) AS actual_revenue,
    t.target,
    ROUND(100 * COALESCE(a.revenue,0) / NULLIF(t.target,0), 1) AS attainment_pct,
    COALESCE(a.revenue,0) - t.target AS variance
FROM sales_target t
LEFT JOIN monthly_actuals a
  ON a.month_start = t.order_date
 AND a.category    = t.category
ORDER BY month_start, category;

-- (c) Company-level monthly target tracking
WITH actuals AS (
  SELECT DATE_FORMAT(o.order_date, '%Y-%m-01') AS month_start,
         SUM(d.amount) AS revenue
  FROM list_of_orders o
  JOIN order_details d USING (order_id)
  GROUP BY month_start
),
targets AS (
  SELECT order_date AS month_start, SUM(target) AS target
  FROM sales_target
  GROUP BY order_date
)
SELECT a.month_start,
       a.revenue AS actual_revenue,
       t.target  AS target_revenue,
       ROUND(100 * a.revenue / NULLIF(t.target,0), 1) AS attainment_pct,
       a.revenue - t.target AS variance
FROM actuals a
LEFT JOIN targets t USING (month_start)
ORDER BY a.month_start;

-- 6) Cohort-style retention (first purchase month → repeat in later months)
WITH first_purchase AS (
  SELECT customer_name,
         MIN(DATE_FORMAT(order_date, '%Y-%m-01')) AS cohort_month
  FROM list_of_orders
  GROUP BY customer_name
),
purchases AS (
  SELECT o.customer_name,
         DATE_FORMAT(o.order_date, '%Y-%m-01') AS order_month
  FROM list_of_orders o
),
cohort_matrix AS (
  SELECT f.cohort_month,
         p.order_month,
         COUNT(DISTINCT p.customer_name) AS active_customers
  FROM first_purchase f
  JOIN purchases p ON p.customer_name = f.customer_name
  GROUP BY f.cohort_month, p.order_month
)
SELECT cohort_month,
       order_month,
       active_customers
FROM cohort_matrix
ORDER BY cohort_month, order_month;

-- 7) SLA/Operational checks can visualize
-- Orders per weekday (staffing insight)
SELECT DAYNAME(order_date) AS weekday,
       COUNT(DISTINCT order_id) AS orders,
       SUM(d.amount) AS revenue
FROM list_of_orders o
JOIN order_details d USING (order_id)
GROUP BY weekday
ORDER BY FIELD(weekday,'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday');

-- High-loss sub-categories to fix
SELECT sub_category,
       SUM(amount) AS revenue,
       SUM(profit) AS profit,
       ROUND(100*SUM(profit)/NULLIF(SUM(amount),0),2) AS margin_pct
FROM order_details
GROUP BY sub_category
HAVING SUM(profit) < 0
ORDER BY margin_pct ASC, revenue DESC;

-- View: Order-level rollup
CREATE OR REPLACE VIEW vw_orders AS
SELECT o.order_id, o.order_date, o.customer_name, o.state, o.city,
       SUM(d.amount)  AS revenue,
       SUM(d.profit)  AS profit,
       SUM(d.quantity) AS units
FROM list_of_orders o
JOIN order_details d USING (order_id)
GROUP BY o.order_id, o.order_date, o.customer_name, o.state, o.city;

-- View: Monthly category actuals vs targets
CREATE OR REPLACE VIEW vw_monthly_cat_vs_target AS
WITH monthly_actuals AS (
  SELECT DATE_FORMAT(o.order_date, '%Y-%m-01') AS month_start,
         d.category,
         SUM(d.amount) AS revenue
  FROM list_of_orders o
  JOIN order_details d USING (order_id)
  GROUP BY month_start, d.category
)
SELECT
  t.order_date AS month_start,
  t.category,
  COALESCE(a.revenue,0) AS actual_revenue,
  t.target,
  COALESCE(a.revenue,0) - t.target AS variance,
  ROUND(100 * COALESCE(a.revenue,0) / NULLIF(t.target,0), 1) AS attainment_pct
FROM sales_target t
LEFT JOIN monthly_actuals a
  ON a.month_start = t.order_date AND a.category = t.category;