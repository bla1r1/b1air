#pragma once
// =============================================================================
// Shape — the corner rule of the design system, carried down the item tree.
//
// Apple's rule (HIG: Layout, Toolbars): something set inside a rounded
// shape, near its edge, is rounded by the shape's radius less how far in it
// sits, so the two curves run parallel. Every element choosing its radius
// from a list (8, 12, 20) got that right only by chance.
//
// A container says what it is: its radius and how far in its content sits
//
//   Rectangle { radius: 20; Shape.radius: 20; Shape.inset: 8 }
//
// and everything inside reads the radius it should have, its own where the
// rule has none (Design.corner; read in QML, so the binding follows it):
//
//   Rectangle { radius: Design.corner(Shape.radius, Design.s(Design.radius.ctl)) }
//
// The value goes down by itself (QQuickAttachedPropertyPropagator, as the
// Controls styles pass their colours down) to the elements that read it,
// through any item that does not; an element that only reads it keeps it,
// and only a container — one that states its radius or its inset — passes
// one on. Where the content sits as far in as the corner is round, or
// further, the rule says nothing — a button in the middle of a card is not
// at its corner — and `radius` is -1: the element keeps its own.
// =============================================================================

#include <QtQuickControls2/qquickattachedpropertypropagator.h>
#include <qqml.h>

class Shape : public QQuickAttachedPropertyPropagator {
    Q_OBJECT
    // The radius this item should have: stated, or what its container leaves
    // its content (-1: no rule here).
    Q_PROPERTY(qreal radius READ radius WRITE setRadius RESET resetRadius NOTIFY radiusChanged FINAL)
    // How far in this item's content sits from its edge, its padding.
    Q_PROPERTY(qreal inset READ inset WRITE setInset NOTIFY insetChanged FINAL)
    // What it leaves its content: radius less inset, never below `minimum`;
    // -1 where the content sits as far in as the corner is round, where
    // there is no rule, or where this is not a container (states neither
    // radius nor inset).
    Q_PROPERTY(qreal inner READ inner NOTIFY innerChanged FINAL)
    // What the container above leaves this item, whatever it states itself:
    // for a container (Ui/Surface) to take its own corner from the rule and
    // state it for what it holds, without reading back its own statement.
    Q_PROPERTY(qreal given READ given NOTIFY givenChanged FINAL)
    // The smallest radius the rule hands out (Design.radius.sm, scaled).
    Q_PROPERTY(qreal minimum READ minimum WRITE setMinimum NOTIFY minimumChanged FINAL)

public:
    explicit Shape(QObject* parent = nullptr);

    static Shape* qmlAttachedProperties(QObject* object);

    qreal radius() const { return m_radius; }
    void setRadius(qreal r);
    void resetRadius();

    qreal inset() const { return m_inset; }
    void setInset(qreal i);

    qreal minimum() const { return m_minimum; }
    void setMinimum(qreal m);

    qreal inner() const;
    qreal given() const { return m_given; }

signals:
    void radiusChanged();
    void insetChanged();
    void innerChanged();
    void minimumChanged();
    void givenChanged();

protected:
    void attachedParentChange(QQuickAttachedPropertyPropagator* newParent,
                              QQuickAttachedPropertyPropagator* oldParent) override;

private:
    void inherit(qreal radius, qreal minimum);
    void propagate();

    qreal m_radius = -1;
    qreal m_given = -1;
    qreal m_inset = 0;
    qreal m_minimum = 4;
    bool m_explicitRadius = false;
    bool m_explicitMinimum = false;
    bool m_explicitInset = false;
};

QML_DECLARE_TYPEINFO(Shape, QML_HAS_ATTACHED_PROPERTIES)
