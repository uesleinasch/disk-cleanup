enum WidthClass { compact, medium, expanded, large }

WidthClass widthClassOf(double width) {
  if (width < 600) return WidthClass.compact;
  if (width < 840) return WidthClass.medium;
  if (width < 1200) return WidthClass.expanded;
  return WidthClass.large;
}
