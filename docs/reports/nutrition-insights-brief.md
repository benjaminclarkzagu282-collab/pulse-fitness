# Task 3b — Nutrition and insights screens
Own only lib/screens/nutrition.dart and lib/screens/insights.dart, plus docs/reports/nutrition-insights-report.md. Do not spawn subagents.

Read lib/core/models.dart, catalog.dart, app_state.dart, lib/ui/components.dart and theme.dart. Approved visual reference: docs/design-board-b.png. App root creates NutritionScreen(state: AppState) and InsightsScreen(state: AppState), both Stateless/StatefulWidget, inside its own scroll view. Do not add outer Scaffold or main scroll view. State changes are observed by ancestor, so use same AppState instance. Dark charcoal, lime accents, dense but readable, wide layout using TwoColumns and mobile stacked. PageTitle labels: nutrition title '健康饮食'; insights title '每一次努力，都算数'.

Nutrition requirements:
- Nutrient progress summary uses ACTUAL state.nutrition, target state.calorieTarget. Protein/carbs/fat are gram estimates, no invented health targets. Label meal estimates, and let user modify energy/water targets, diet (均衡饮食/素食优先), allergen exclusions(鸡蛋/乳制品/大豆/坚果/海鲜) with savePreferences.
- Four meal rows from state.meals, mealById; portion multiplier display; buttons record/undo via toggleMeal, choose alternative and amount via setMeal. Changing planned meal must visibly show logged record is preserved until user undoes/re-records. Menu options come from availableMeals(slot), all choices prefiltered.
- Display each meal's kcal/protein/carbs/fat estimates; choose meal in modal with radio options and portion .5,1,1.5,2.
- Water +/-250 record, clamp handled store.
- Information and actions meaningful, no dead controls or false placeholder promises.
- Can use emoji for food thumbnails or local assets/images/meals.png if it exists (root may create); don't require it.

Insights requirements:
- ScoreRing + three bars from score; explanatory modal states 60% training(set completion),30% meals(record completeness),10% water, score indicates adherence not physiological health. Explicit no score reward for consuming less.
- history period 7/30 selectable with MiniChart or scrollable columns. Days without activity have null, do not show fake zeros as actual records. Actual log summary exercise sets, logged meals, water, time. Show clear empty history.
- state.recommendation provides tomorrow date, editable plan, meals, reasons and nutritionReason. Allow edit next plan duration/sets/reps/rest or remove exercise in a modal (local NextRecommendation draft), meal swaps/portion modifications local. Do not mutate today's plan or logged meals.
- Primary adopt uses state.adoptRecommendation(draft) only when user clicks; after adopts render saved plans[tomorrow]/mealPlans[tomorrow] so view matches saved data. Can build recommendation copy manually with constructor. Subsequent edits and re-adopt work. Do not blindly revert to freshly generated recommendation after adopting.
- Explain high fatigue/current little history naturally with provided strings. Both training and food suggestions editable, transparent reasons visible, explicit date.

Use existing components: PageTitle(eyebrow,title,subtitle,trailing), SectionTitle(title,action,onTap), Panel(child,padding,color), Pill(label,active,onTap,icon), Tag(label,color), ThinBar(value,color,height), Stat(value,label,color), ScoreRing(score,size), ExerciseThumb(exercise,width,height), TwoColumns(left,right,breakAt,leftFlex,rightFlex), MiniChart(values,labels), showAppSheet<T>(context,Widget), toast(context,text). Parent app handles spacing and scrolling.

Make files compile; do not modify shared API files. Run `dart format` on your files (SDK /Users/jiyibo/.local/share/flutter/bin/dart), targeted `flutter analyze lib/screens/nutrition.dart lib/screens/insights.dart` (other app files may be incomplete). Report exact evidence and any API issues to root. Commit only your two screen files and report, no other files.
