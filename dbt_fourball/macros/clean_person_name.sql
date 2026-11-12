{#
  Standardize a scraped player name to "First Last":
    "Qi (Steven) Liu" -> "Qi Liu"       nickname dropped
    "Michael Martin1" -> "Michael Martin" stray digits
    "Paul  Mittman"   -> "Paul Mittman"   whitespace
    "Sorger, Maxwell" -> "Maxwell Sorger" flipped; "Barron, III, Peter" -> "Peter Barron III"
    "DEXTER RICE"     -> "Dexter Rice"    all-caps/lower only; mixed case ("McNeill") is kept as-is
  BlueGolf surname-only names ("Seger") can't be expanded and stay as they are.
#}
{% macro clean_person_name(col) -%}
{%- set stripped -%}
trim(regexp_replace(regexp_replace(regexp_replace({{ col }}, '[(][^)]*[)]', ''), '[0-9]+', ''), '[[:space:]]+', ' '))
{%- endset -%}
{%- set flipped -%}
case
    when regexp_count({{ stripped }}, ',') = 2   -- "Barron, III, Peter" -> "Peter Barron III"
        then trim(split_part({{ stripped }}, ',', 3)) || ' ' || trim(split_part({{ stripped }}, ',', 1)) || ' ' || trim(split_part({{ stripped }}, ',', 2))
    when regexp_like({{ stripped }}, '.*,[[:space:]]*(Jr|Sr|II|III|IV)[.]?')   -- "Audette, Jr." -> "Audette Jr."
        then replace({{ stripped }}, ',', '')
    when regexp_count({{ stripped }}, ',') = 1
        then trim(split_part({{ stripped }}, ',', 2)) || ' ' || trim(split_part({{ stripped }}, ',', 1))
    else {{ stripped }}
end
{%- endset -%}
nullif(iff({{ flipped }} = upper({{ flipped }}) or {{ flipped }} = lower({{ flipped }}), initcap({{ flipped }}, ' -'''), {{ flipped }}), '')
{%- endmacro %}
