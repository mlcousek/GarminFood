## ADDED Requirements

### Requirement: Czech product names are used when Open Food Facts has them

The system SHALL request and prefer Open Food Facts' Czech name fields when
searching and displaying Czech products:

1. `product_name_cs`
2. `generic_name_cs`
3. `product_name`, as the fallback

The system SHALL use Search-a-licious (`search.openfoodfacts.org`, to be
probed and recorded before use), falling back to `cgi/search.pl` when it is
unavailable.

#### Scenario: Czech-only name field

- **WHEN** a product's `product_name` is English but `product_name_cs` is "Kefírové mléko"
- **THEN** the result displays "Kefírové mléko" and matches the query "kefir"

#### Scenario: Primary endpoint down

- **WHEN** Search-a-licious returns an error
- **THEN** the same query is answered from `cgi/search.pl` and results still appear
