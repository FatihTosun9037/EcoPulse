using System.Windows;
using System.Windows.Media;

namespace EcoPulse.Dashboard;

public sealed class Sparkline : FrameworkElement
{
    public static readonly DependencyProperty LineBrushProperty = DependencyProperty.Register(
        nameof(LineBrush),
        typeof(Brush),
        typeof(Sparkline),
        new FrameworkPropertyMetadata(Brushes.White, FrameworkPropertyMetadataOptions.AffectsRender));

    public Brush LineBrush
    {
        get => (Brush)GetValue(LineBrushProperty);
        set => SetValue(LineBrushProperty, value);
    }

    private IReadOnlyList<double> _values = Array.Empty<double>();

    public Sparkline()
    {
        SnapsToDevicePixels = true;
    }

    public void SetValues(IReadOnlyList<double> values)
    {
        _values = values;
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        IReadOnlyList<double> values = _values;
        double width = ActualWidth;
        double height = ActualHeight;
        if (values.Count < 2 || width < 8 || height < 8)
        {
            return;
        }

        const double inset = 6;
        double plotWidth = width - (inset * 2);
        double plotHeight = height - (inset * 2);
        double min = values.Min();
        double max = values.Max();
        double pad = (max - min) * 0.16;
        if (pad < 0.001)
        {
            pad = 1;
        }

        min -= pad;
        max += pad;

        Point At(int index)
        {
            double x = inset + (index * plotWidth / (values.Count - 1));
            double y = inset + plotHeight - ((values[index] - min) / (max - min) * plotHeight);
            return new Point(x, y);
        }

        Color lineColor = LineBrush is SolidColorBrush solid ? solid.Color : Color.FromRgb(0xE4, 0xE7, 0xEB);
        var gridBrush = new SolidColorBrush(Color.FromArgb(70, 0x5C, 0x67, 0x74));
        var gridPen = new Pen(gridBrush, 1);
        for (int line = 1; line <= 2; line++)
        {
            double y = inset + (plotHeight * line / 3);
            dc.DrawLine(gridPen, new Point(inset, y), new Point(width - inset, y));
        }

        var lineGeometry = new StreamGeometry();
        var fillGeometry = new StreamGeometry();
        using (StreamGeometryContext lineContext = lineGeometry.Open())
        using (StreamGeometryContext fillContext = fillGeometry.Open())
        {
            Point first = At(0);
            lineContext.BeginFigure(first, false, false);
            fillContext.BeginFigure(first, true, true);
            for (int index = 1; index < values.Count; index++)
            {
                Point point = At(index);
                lineContext.LineTo(point, true, true);
                fillContext.LineTo(point, true, false);
            }

            Point last = At(values.Count - 1);
            fillContext.LineTo(new Point(last.X, height - inset), true, false);
            fillContext.LineTo(new Point(first.X, height - inset), true, false);
        }

        lineGeometry.Freeze();
        fillGeometry.Freeze();
        var fillBrush = new SolidColorBrush(Color.FromArgb(22, lineColor.R, lineColor.G, lineColor.B));
        dc.DrawGeometry(fillBrush, null, fillGeometry);

        var pen = new Pen(LineBrush, 1.6)
        {
            StartLineCap = PenLineCap.Flat,
            EndLineCap = PenLineCap.Flat,
            LineJoin = PenLineJoin.Miter
        };
        if (pen.CanFreeze)
        {
            pen.Freeze();
        }

        dc.DrawGeometry(null, pen, lineGeometry);

        Point end = At(values.Count - 1);
        dc.DrawRectangle(LineBrush, null, new Rect(end.X - 2.2, end.Y - 2.2, 4.4, 4.4));
    }
}
