import Either
import Foundation
import Optics
import Prelude

extension Optional {
  public enum iso {
    /// A partial isomorphism `(A) -> A?` 
    public static var some: PartialIso<Wrapped, Wrapped?> {
      return PartialIso<Wrapped, Wrapped?>(
        image: { .some($0) },
        preimage: { $0 }
      )
    }
  }
}

/// Lifts a partial isomorphism `(A) -> B` to one `(A) -> B?`.
public func opt<A, B>(_ f: PartialIso<A, B>) -> PartialIso<A, B?> {
  return f >>> Optional.iso.some
}

extension PartialIso where A == String, B == Int {
  /// An isomorphism between strings and integers.
  public static var int: PartialIso {
    return .init(
      image: Int.init,
      preimage: String.init
    )
  }
}

// TODO: possible to document this in the applicative of Syntax?

extension PartialIso where A == String, B == Bool {
  /// An isomorphism between strings and booleans.
  public static var bool: PartialIso {
    return .init(
      image: {
        $0 == "true" || $0 == "1" ? true
          : $0 == "false" || $0 == "0" ? false
          : nil
      },
      preimage: { $0 ? "true" : "false" }
    )
  }
}

extension PartialIso where A == String, B == String {
  /// The identity isomorphism between strings.
  public static var string: PartialIso {
    return .id
  }
}

extension PartialIso where A == String, B == Double {
  /// An isomorphism between strings and doubles.
  public static var double: PartialIso {
    return .init(
      image: Double.init,
      preimage: String.init
    )
  }
}

extension PartialIso where A == String, B == [String: String] {
  /// An isomorphism between strings and dictionaries using form encoded format.
  public static var formEncodedFields: PartialIso<String, [String: String]> {
    return .init(
      image: formEncodedStringToFields,
      preimage: fieldsToFormEncodedString
    )
  }
}

extension PartialIso where A == String, B == Data {
  /// An isomorphism between strings and data using utf8 encoding.
  /// TODO: this should prob take encoding as an argument.
  public static var data: PartialIso<String, Data> {
    return .init(
      image: { Data($0.utf8) },
      preimage: { String(data: $0, encoding: .utf8) }
    )
  }
}

extension PartialIso where A: Codable, B == Data {
  public static var codableToData: PartialIso<A, Data> {
    return .init(
      image: { try? JSONEncoder().encode($0) },
      preimage: { try? JSONDecoder().decode(A.self, from: $0) }
    )
  }
}

public let jsonDictionaryToData = PartialIso<[String: String], Data>(
  image: { try? JSONSerialization.data(withJSONObject: $0) },
  preimage: {
    (try? JSONSerialization.jsonObject(with: $0))
      .flatMap { $0 as? [String: String] }
})

public func key<K, V>(_ key: K) -> PartialIso<[K: V], V> {
  return PartialIso<[K: V], V>(
    image: { $0[key] },
    preimage: { [key: $0] }
  )
}

public func keys<K, V>(_ keys: [K]) -> PartialIso<[K: V], [K: V]> {
  return .init(
    image: { $0.filter { key, _ in keys.contains(key) } },
    preimage: id
  )
}

extension PartialIso where A == String, B == Either<String, Int> {
  public static var intOrString: PartialIso<String, Either<String, Int>> {
    return PartialIso<String, Either<String, Int>>(
      image: { Int($0).map(Either.right) ?? .left($0) },
      preimage: { $0.right.map(String.init) ?? $0.left }
    )
  }
}

private func formEncodedStringToFields(_ body: String) -> [String: String] {
  let pairs = body.split(separator: "&")
    .map {
      $0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        .flatMap(String.init >>> Prelude.get(\.removingPercentEncoding))
    }
    .map { ($0[0], $0[1]) }
  return [String: String](uniqueKeysWithValues: pairs)
}

private func fieldsToFormEncodedString(_ data: [String: String]) -> String {
  let t = URLComponents()
    |> \.queryItems .~ data.map(URLQueryItem.init(name:value:))
  return t.query ?? ""
}
