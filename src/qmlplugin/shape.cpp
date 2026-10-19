#include "shape.hpp"

#include <algorithm>

Shape::Shape(QObject* parent) : QQuickAttachedPropertyPropagator(parent) {
    // Finds the nearest Shape above (an item's parent, a popup's, a
    // window's) and takes what it leaves.
    initialize();
}

Shape* Shape::qmlAttachedProperties(QObject* object) {
    return new Shape(object);
}

qreal Shape::inner() const {
    if (m_radius < 0) return -1;
    // Only a container passes the rule on: one that says how far in its
    // content sits, or is a shape of its own. A button that took its radius
    // from the row it is in does not hand it to what is inside the button.
    if (!m_explicitRadius && !m_explicitInset) return -1;
    const qreal left = m_radius - m_inset;
    // As far in as the corner is round, or further: the corner does not
    // reach it, and the rule has nothing to say.
    if (left <= 0) return -1;
    return std::max(left, m_minimum);
}

void Shape::setRadius(qreal r) {
    m_explicitRadius = true;
    if (qFuzzyCompare(m_radius + 1, r + 1)) return;
    const qreal before = inner();
    m_radius = r;
    emit radiusChanged();
    if (!qFuzzyCompare(before + 1, inner() + 1)) { emit innerChanged(); propagate(); }
}

void Shape::resetRadius() {
    if (!m_explicitRadius) return;
    m_explicitRadius = false;
    if (auto* p = qobject_cast<Shape*>(attachedParent())) inherit(p->inner(), p->minimum());
    else inherit(-1, m_minimum);
}

void Shape::setInset(qreal i) {
    if (!m_explicitInset) {
        m_explicitInset = true;
        if (qFuzzyCompare(m_inset + 1, i + 1)) {
            // Now a container, at the same inset: what it passes on changed.
            emit innerChanged();
            propagate();
            return;
        }
    }
    if (qFuzzyCompare(m_inset + 1, i + 1)) return;
    const qreal before = inner();
    m_inset = i;
    emit insetChanged();
    if (!qFuzzyCompare(before + 1, inner() + 1)) { emit innerChanged(); propagate(); }
}

void Shape::setMinimum(qreal m) {
    m_explicitMinimum = true;
    if (qFuzzyCompare(m_minimum + 1, m + 1)) return;
    const qreal before = inner();
    m_minimum = m;
    emit minimumChanged();
    if (!qFuzzyCompare(before + 1, inner() + 1)) emit innerChanged();
    propagate();
}

// What the container leaves, taken unless this item states its own.
void Shape::inherit(qreal radius, qreal minimum) {
    if (!qFuzzyCompare(m_given + 1, radius + 1)) {
        m_given = radius;
        emit givenChanged();
    }
    const qreal before = inner();
    if (!m_explicitMinimum && !qFuzzyCompare(m_minimum + 1, minimum + 1)) {
        m_minimum = minimum;
        emit minimumChanged();
    }
    if (!m_explicitRadius && !qFuzzyCompare(m_radius + 1, radius + 1)) {
        m_radius = radius;
        emit radiusChanged();
    }
    if (!qFuzzyCompare(before + 1, inner() + 1)) emit innerChanged();
    propagate();
}

void Shape::propagate() {
    const auto children = attachedChildren();
    for (QQuickAttachedPropertyPropagator* child : children) {
        if (auto* s = qobject_cast<Shape*>(child)) s->inherit(inner(), m_minimum);
    }
}

void Shape::attachedParentChange(QQuickAttachedPropertyPropagator* newParent,
                                 QQuickAttachedPropertyPropagator*) {
    if (auto* p = qobject_cast<Shape*>(newParent)) inherit(p->inner(), p->minimum());
    else inherit(-1, m_minimum);
}
