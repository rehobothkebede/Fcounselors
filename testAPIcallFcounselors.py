from openai import OpenAI

try:
    client = OpenAI()
    response = client.responses.create(
        model="gpt-5.2",
        input="Give me a one sentence motivational quote."
    )
    
    print("✅ API call succeeded")
    print(response.output[0].content[0].text)

except Exception as e:
    print("❌ Something went wrong:")
    print(e)
