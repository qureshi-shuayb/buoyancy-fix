
# Refactor to Design System
Refactor the Star Deli website as it has duplicated code for 3 different screen sizes.


## Files

- `/app/index.html` - Contains duplicate HTML and CSS for 3 screen sizes



## Requirements for Success
- One set of copy - Write the page content once rather the 3 times
- Consolidate and Deduplicate the CSS
- mobile-first CSS
- Use media queries

- call to order should only appear in mobile
- In Mobile products are above hero section, hide hero image, make the call to order bar visible
- In Tablet hero section above products, hero image visible
- Desktop "Free delivery"  banner visible, hero above products
- All sizes, header, 3 cards (Sernik/Pączki/Makowiec), and footer should be there
- laptop view (769–1024px) must be built, currently laptops have 2 columns, for laptop show product in 3 columns,hero above products, hero image visible, no call bar, no promo




## Tests Verify
- remove duplicate HTML copy
- the page should look the same at each breakpoint as the original
